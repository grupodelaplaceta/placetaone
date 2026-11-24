begin;
-- Placeta One · 0067 · Placeta Joven: cuenta joven por DIP, compras con IVA, recargas y movimientos.
-- Las cuentas joven solo mueven dinero con cuentas joven, de administración (system) o comercios Joven.
-- La regla se aplica con un disparador diferido sobre el libro mayor. Requiere 0066. Idempotente. NO ejecutado en PostgreSQL.

-- 1) Nuevo tipo de cuenta y marca de comercio Joven
do $$ declare r record; begin
  for r in select c.conname from pg_constraint c join pg_class t on t.oid=c.conrelid
           where t.relname='plone27_accounts' and c.contype='c' and pg_get_constraintdef(c.oid) like '%kind%' loop
    execute format('alter table plone27_accounts drop constraint %I', r.conname);
  end loop;
end $$;
alter table plone27_accounts add constraint plone27_accounts_kind_check
  check(kind in('personal','business','shared','junior','system','joven'));
alter table plone27_accounts add column if not exists comercio_joven boolean not null default false;

-- 2) Cuentas Joven por persona y pagos con desglose de IVA
create table if not exists plone27_joven_cuentas(
  account_id uuid primary key references plone27_accounts(id),
  bank_id uuid not null references plone27_banks(id),
  persona uuid not null references plone27_personas(id),
  dip text not null,
  creada timestamptz not null default now(),
  unique(bank_id,persona));

create table if not exists plone27_joven_pagos(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks(id),
  clave text not null unique,
  joven uuid not null references plone27_accounts(id),
  comercio uuid not null references plone27_accounts(id),
  importe numeric(18,2) not null check(importe>0),
  base numeric(18,2) not null,
  iva numeric(18,2) not null,
  iva_pct numeric(5,2) not null,
  tx_base uuid references plone27_transactions(id),
  tx_iva uuid references plone27_transactions(id),
  concepto text,
  creada timestamptz not null default now());

-- 3) Regla de circulación: cada transacción que toca una cuenta Joven solo puede tener contrapartes permitidas
create or replace function plone27_joven_guard() returns trigger language plpgsql as $$
#variable_conflict use_column
declare malas int; begin
  if exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
            where e.transaction_id=new.transaction_id and a.kind='joven') then
    select count(*) into malas from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
      where e.transaction_id=new.transaction_id and a.kind<>'joven'
        and not (a.kind='system' or (a.kind='business' and a.comercio_joven));
    if malas>0 then
      raise exception 'Placeta Joven: el dinero solo puede moverse entre cuentas Joven, administración o comercios Joven';
    end if;
  end if;
  return null; end $$;
drop trigger if exists trg_joven_guard on plone27_ledger_entries;
create constraint trigger trg_joven_guard after insert on plone27_ledger_entries
  deferrable initially deferred for each row execute function plone27_joven_guard();

-- 4) Cuenta Joven de una persona (una por DIP y entidad). Idempotente: devuelve la existente.
create or replace function plone27_joven_cuenta_crear(p_bank uuid,p_dip text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare vc text; per uuid; aid uuid; v_iban text; creada boolean:=false; begin
  select b.code into vc from plone27_banks b where b.id=p_bank and b.status='active';
  if vc is null then raise exception 'Entidad inexistente o no activa'; end if;
  per:=plone27_persona(p_dip);
  select jc.account_id into aid from plone27_joven_cuentas jc where jc.bank_id=p_bank and jc.persona=per;
  if aid is null then
    v_iban:='PZ-'||vc||'-'||lpad(plone27_next_num('ACC',vc,9999)::text,4,'0');
    insert into plone27_accounts(bank_id,kind,name,iban) values(p_bank,'joven','Placeta Joven',v_iban)
      returning plone27_accounts.id into aid;
    insert into plone27_joven_cuentas(account_id,bank_id,persona,dip) values(aid,p_bank,per,plone27_normalizar_dip(p_dip));
    creada:=true;
    insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'joven_cuenta_crear','account',aid::text,jsonb_build_object('iban',v_iban));
  end if;
  return jsonb_build_object('iban',(select a.iban from plone27_accounts a where a.id=aid),'creada',creada); end $$;

-- 5) Cuenta Joven de un DIP, para que el portal la seleccione sola
create or replace function plone27_joven_cuenta_de(p_bank uuid,p_dip text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare per uuid; aid uuid; v_iban text; begin
  select p.id into per from plone27_personas p where p.dip=plone27_normalizar_dip(p_dip);
  if per is null then return null; end if;
  select jc.account_id, a.iban into aid, v_iban from plone27_joven_cuentas jc join plone27_accounts a on a.id=jc.account_id
    where jc.bank_id=p_bank and jc.persona=per and a.status='active';
  if aid is null then return null; end if;
  return jsonb_build_object('iban',v_iban,'disponible',plone27_available(aid)); end $$;

-- 6) Compra en un comercio Joven con IVA desglosado. Base al comercio, IVA a la cuenta recaudadora.
create or replace function plone27_joven_pagar(p_bank uuid,p_joven_iban text,p_comercio_iban text,p_importe numeric,
    p_concepto text,p_clave text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare j uuid; c uuid; col uuid; pct numeric; base numeric; iva numeric; tb uuid; ti uuid; pr plone27_joven_pagos; begin
  if p_importe is null or p_importe<=0 then raise exception 'El importe debe ser mayor que cero'; end if;
  if coalesce(length(p_clave),0)<8 or length(p_clave)>80 then raise exception 'Clave de idempotencia de 8 a 80 caracteres'; end if;
  select * into pr from plone27_joven_pagos where clave=p_clave;
  if pr.id is not null then
    return jsonb_build_object('base',pr.base,'iva',pr.iva,'iva_pct',pr.iva_pct,'total',pr.importe,'repetida',true); end if;
  select a.id into j from plone27_accounts a where a.iban=p_joven_iban and a.bank_id=p_bank and a.kind='joven' and a.status='active';
  if j is null then raise exception 'Cuenta Placeta Joven no encontrada en tu entidad'; end if;
  select a.id into c from plone27_accounts a where a.iban=p_comercio_iban and a.bank_id=p_bank
    and a.kind='business' and a.comercio_joven and a.status='active';
  if c is null then raise exception 'Comercio Placeta Joven no válido'; end if;
  pct:=(plone27_setting('joven_iva_pct')#>>'{}')::numeric;
  base:=round(p_importe/(1+pct/100),2); iva:=p_importe-base;
  select r.collector_account into col from plone27_tax_rules r where r.code='IVA';
  if iva>0 and col is null then raise exception 'No hay cuenta recaudadora de IVA configurada'; end if;
  tb:=plone27_transfer(p_clave||':base',j,c,base,coalesce(p_concepto,'Compra Placeta Joven'),p_actor);
  if iva>0 then ti:=plone27_transfer(p_clave||':iva',j,col,iva,'IVA '||pct||'% · '||coalesce(p_concepto,''),p_actor); end if;
  insert into plone27_joven_pagos(bank_id,clave,joven,comercio,importe,base,iva,iva_pct,tx_base,tx_iva,concepto)
    values(p_bank,p_clave,j,c,p_importe,base,iva,pct,tb,ti,p_concepto);
  return jsonb_build_object('base',base,'iva',iva,'iva_pct',pct,'total',p_importe,
    'transacciones',jsonb_build_array(tb,ti),'repetida',false); end $$;

-- 7) Recarga desde la cuenta de administración (system) de la entidad
create or replace function plone27_joven_recarga(p_bank uuid,p_origen_iban text,p_joven_iban text,p_importe numeric,
    p_concepto text,p_clave text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare o uuid; j uuid; begin
  if p_importe is null or p_importe<=0 then raise exception 'El importe debe ser mayor que cero'; end if;
  if coalesce(length(p_clave),0)<8 or length(p_clave)>80 then raise exception 'Clave de idempotencia de 8 a 80 caracteres'; end if;
  select a.id into o from plone27_accounts a where a.iban=p_origen_iban and a.bank_id=p_bank and a.kind='system' and a.status='active';
  if o is null then raise exception 'La recarga solo puede salir de una cuenta de administración de tu entidad'; end if;
  select a.id into j from plone27_accounts a where a.iban=p_joven_iban and a.bank_id=p_bank and a.kind='joven' and a.status='active';
  if j is null then raise exception 'Cuenta Placeta Joven no encontrada en tu entidad'; end if;
  return plone27_transfer(p_clave,o,j,p_importe,coalesce(p_concepto,'Recarga Placeta Joven'),p_actor); end $$;

-- 8) Movimientos de una cuenta Joven, con contraparte y desglose de IVA cuando lo hay
create or replace function plone27_joven_movimientos(p_bank uuid,p_iban text,p_desde date,p_hasta date,p_limite int) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare j uuid; begin
  select a.id into j from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank and a.kind='joven';
  if j is null then raise exception 'Cuenta Placeta Joven no encontrada en tu entidad'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.fecha desc) from (
    select t.id, e.created_at as fecha,
      case when e.direction='credit' then 'entrada' else 'salida' end as tipo,
      e.amount as importe, coalesce(t.memo,'') as concepto, t.status as estado,
      (select jsonb_build_object('tipo',ca.kind,'nombre',case when ca.kind='joven' then 'Placeta Joven' else ca.name end)
         from plone27_ledger_entries o join plone27_accounts ca on ca.id=o.account_id
        where o.transaction_id=t.id and o.account_id<>j limit 1) as contraparte,
      (select jsonb_build_object('base',pg.base,'iva',pg.iva,'iva_pct',pg.iva_pct)
         from plone27_joven_pagos pg where pg.tx_base=t.id or pg.tx_iva=t.id limit 1) as desglose
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=j and e.created_at::date between p_desde and p_hasta
    order by e.created_at desc
    limit greatest(1,least(coalesce(p_limite,50),200))
  ) x), '[]'::jsonb); end $$;

-- 9) Marcar o quitar un comercio Joven (solo empresas). Lo hace la Junta.
create or replace function plone27_joven_comercio_marcar(p_iban text,p_activo boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  update plone27_accounts set comercio_joven=p_activo where iban=p_iban and kind='business';
  if not found then raise exception 'Solo una cuenta de empresa (business) puede ser comercio Joven'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'joven_comercio','account',p_iban,jsonb_build_object('activo',p_activo)); end $$;

-- 10) Ajuste editable: IVA de las compras Joven (sensible: doble firma)
insert into plone27_settings(key,category,description,vtype,min_v,max_v,value,sensitive,bank_overridable)
  values('joven_iva_pct','joven','IVA aplicado a las compras de Placeta Joven (%). El precio que paga la persona ya lo incluye.','number',0,30,'12',true,false)
  on conflict (key) do nothing;

-- Seguridad (mismo patrón; no legibles desde el panel)
do $$ declare t text; f text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces','plone27_personas') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

do $$ begin raise notice 'Actualización 0067 aplicada correctamente.'; end $$;

commit;
