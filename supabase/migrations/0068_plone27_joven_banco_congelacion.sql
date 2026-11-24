-- Placeta One · 0068 · Placeta Joven: las cuentas son de Banco de La Placeta, se pueden congelar,
-- y los demás bancos solo las leen. Ningún movimiento sobre una cuenta Joven sale sin la marca de Placeta Joven.
-- Requiere 0067. Idempotente. NO ejecutado en PostgreSQL.

-- 1) El banco de Placeta Joven (debe existir: créalo desde Bancos con el nombre exacto)
create or replace function plone27_banco_joven() returns uuid language plpgsql stable security definer set search_path=public as $$
declare b uuid; begin
  select id into b from plone27_banks where name='Banco de La Placeta';
  if b is null then raise exception 'Falta el banco "Banco de La Placeta": créalo en Bancos antes de usar Placeta Joven'; end if;
  return b; end $$;

-- Cuentas Joven ya existentes pasan a ese banco (si ya existe)
do $$ declare b uuid; begin
  select id into b from plone27_banks where name='Banco de La Placeta';
  if b is not null then
    update plone27_accounts set bank_id=b where kind='joven' and bank_id<>b;
    update plone27_joven_cuentas set bank_id=b where bank_id<>b;
  end if;
end $$;

-- 2) Congelación de la cuenta (la pone Placeta Joven por suscripción)
alter table plone27_joven_cuentas add column if not exists congelada boolean not null default false;
alter table plone27_joven_cuentas add column if not exists congelada_motivo text;
alter table plone27_joven_cuentas add column if not exists congelada_at timestamptz;

-- 3) Guardián: marca obligatoria, cuentas congeladas bloqueadas y circulación limitada
create or replace function plone27_joven_guard() returns trigger language plpgsql as $$
#variable_conflict use_column
declare malas int; congeladas int; begin
  if exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
            where e.transaction_id=new.transaction_id and a.kind='joven') then
    if coalesce(current_setting('plone27.joven_op', true),'')<>'on' then
      raise exception 'Las cuentas Placeta Joven solo se operan desde Placeta Joven';
    end if;
    select count(*) into congeladas from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
      join plone27_joven_cuentas jc on jc.account_id=a.id
      where e.transaction_id=new.transaction_id and jc.congelada;
    if congeladas>0 then raise exception 'Cuenta Placeta Joven congelada: no admite movimientos'; end if;
    select count(*) into malas from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
      where e.transaction_id=new.transaction_id and a.kind<>'joven'
        and not (a.kind='system' or (a.kind='business' and a.comercio_joven));
    if malas>0 then
      raise exception 'Placeta Joven: el dinero solo puede moverse entre cuentas Joven, administración o comercios Joven';
    end if;
  end if;
  return null; end $$;

-- 4) Crear la cuenta: solo Banco de La Placeta
create or replace function plone27_joven_cuenta_crear(p_bank uuid,p_dip text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare vc text; per uuid; aid uuid; v_iban text; creada boolean:=false; begin
  if p_bank is distinct from plone27_banco_joven() then raise exception 'Solo Banco de La Placeta opera Placeta Joven'; end if;
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

-- 5) Lectura de una cuenta Joven por IBAN (cualquier banco con joven:leer). No muestra el DIP.
create or replace function plone27_joven_leer(p_iban text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare aid uuid; begin
  select a.id into aid from plone27_accounts a where a.iban=p_iban and a.kind='joven';
  if aid is null then return null; end if;
  return (select jsonb_build_object('iban',a.iban,'estado',a.status,'congelada',coalesce(jc.congelada,false),
      'motivo_congelacion',case when jc.congelada then jc.congelada_motivo end,
      'disponible',plone27_available(a.id),'banco',b.name)
    from plone27_accounts a join plone27_banks b on b.id=a.bank_id left join plone27_joven_cuentas jc on jc.account_id=a.id
    where a.id=aid); end $$;

-- 6) Congelar o descongelar: solo Banco de La Placeta
create or replace function plone27_joven_congelar(p_bank uuid,p_iban text,p_congelada boolean,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare aid uuid; begin
  if p_bank is distinct from plone27_banco_joven() then raise exception 'Solo Banco de La Placeta gestiona Placeta Joven'; end if;
  if p_congelada and coalesce(length(p_motivo),0)<10 then raise exception 'Para congelar, el motivo debe tener al menos 10 caracteres'; end if;
  select a.id into aid from plone27_accounts a where a.iban=p_iban and a.kind='joven' and a.bank_id=p_bank;
  if aid is null then raise exception 'Cuenta Placeta Joven no encontrada'; end if;
  update plone27_joven_cuentas set congelada=p_congelada,
    congelada_motivo=case when p_congelada then p_motivo end,
    congelada_at=case when p_congelada then now() end
    where account_id=aid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,case when p_congelada then 'joven_congelar' else 'joven_descongelar' end,'account',aid::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- 7) Compra: solo Banco de La Placeta, cuentas no congeladas, y marca de operación Joven
create or replace function plone27_joven_pagar(p_bank uuid,p_joven_iban text,p_comercio_iban text,p_importe numeric,
    p_concepto text,p_clave text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare j uuid; c uuid; col uuid; pct numeric; base numeric; iva numeric; tb uuid; ti uuid; pr plone27_joven_pagos; begin
  if p_bank is distinct from plone27_banco_joven() then raise exception 'Solo Banco de La Placeta opera Placeta Joven'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'El importe debe ser mayor que cero'; end if;
  if coalesce(length(p_clave),0)<8 or length(p_clave)>80 then raise exception 'Clave de idempotencia de 8 a 80 caracteres'; end if;
  select * into pr from plone27_joven_pagos where clave=p_clave;
  if pr.id is not null then
    return jsonb_build_object('base',pr.base,'iva',pr.iva,'iva_pct',pr.iva_pct,'total',pr.importe,'repetida',true); end if;
  select a.id into j from plone27_accounts a where a.iban=p_joven_iban and a.bank_id=p_bank and a.kind='joven' and a.status='active';
  if j is null then raise exception 'Cuenta Placeta Joven no encontrada'; end if;
  if exists(select 1 from plone27_joven_cuentas where account_id=j and congelada) then raise exception 'Cuenta Placeta Joven congelada: no admite movimientos'; end if;
  select a.id into c from plone27_accounts a where a.iban=p_comercio_iban and a.bank_id=p_bank
    and a.kind='business' and a.comercio_joven and a.status='active';
  if c is null then raise exception 'Comercio Placeta Joven no válido'; end if;
  perform set_config('plone27.joven_op','on',true);
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

-- 8) Recarga: solo Banco de La Placeta, desde administración, sin congelar
create or replace function plone27_joven_recarga(p_bank uuid,p_origen_iban text,p_joven_iban text,p_importe numeric,
    p_concepto text,p_clave text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare o uuid; j uuid; begin
  if p_bank is distinct from plone27_banco_joven() then raise exception 'Solo Banco de La Placeta opera Placeta Joven'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'El importe debe ser mayor que cero'; end if;
  if coalesce(length(p_clave),0)<8 or length(p_clave)>80 then raise exception 'Clave de idempotencia de 8 a 80 caracteres'; end if;
  select a.id into o from plone27_accounts a where a.iban=p_origen_iban and a.bank_id=p_bank and a.kind='system' and a.status='active';
  if o is null then raise exception 'La recarga solo puede salir de una cuenta de administración de tu entidad'; end if;
  select a.id into j from plone27_accounts a where a.iban=p_joven_iban and a.bank_id=p_bank and a.kind='joven' and a.status='active';
  if j is null then raise exception 'Cuenta Placeta Joven no encontrada'; end if;
  if exists(select 1 from plone27_joven_cuentas where account_id=j and congelada) then raise exception 'Cuenta Placeta Joven congelada: no admite movimientos'; end if;
  perform set_config('plone27.joven_op','on',true);
  return plone27_transfer(p_clave,o,j,p_importe,coalesce(p_concepto,'Recarga Placeta Joven'),p_actor); end $$;

-- 9) Movimientos: con p_bank informado solo de ese banco; con null (lectura) de cualquier banco
create or replace function plone27_joven_movimientos(p_bank uuid,p_iban text,p_desde date,p_hasta date,p_limite int) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare j uuid; begin
  select a.id into j from plone27_accounts a where a.iban=p_iban and a.kind='joven' and (p_bank is null or a.bank_id=p_bank);
  if j is null then raise exception 'Cuenta Placeta Joven no encontrada'; end if;
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
