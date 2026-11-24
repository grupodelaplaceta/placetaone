begin;
-- Placeta One · 0069 · Placeta Joven: edad de 16 a 31 años, con periodo de gracia hasta el 31 de diciembre
-- del año en que se cumplen los 31. Se comprueba al abrir la cuenta, en cada operación y cada día (congelación automática).
-- Requiere 0068. Idempotente. NO ejecutado en PostgreSQL.

alter table plone27_joven_cuentas add column if not exists fecha_nacimiento date;

-- Elegible: la persona cumple 31 en el año Y y puede operar hasta el 31 de diciembre de Y.
create or replace function plone27_joven_vigente(p_nacimiento date) returns boolean
language sql stable as $$
  select p_nacimiento is not null and extract(year from current_date)::int <= extract(year from p_nacimiento)::int + 31 $$;

-- Alta: exige 16 años cumplidos y elegibilidad. Guarda la fecha de nacimiento verificada.
create or replace function plone27_joven_alta(p_bank uuid,p_dip text,p_nacimiento date,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare per uuid; previa date; r jsonb; begin
  if p_nacimiento is null then raise exception 'Indica la fecha de nacimiento'; end if;
  if p_nacimiento>current_date then raise exception 'La fecha de nacimiento no puede ser futura'; end if;
  if age(current_date,p_nacimiento)<interval '16 years' then raise exception 'Placeta Joven es para personas de 16 años o más'; end if;
  if not plone27_joven_vigente(p_nacimiento) then
    raise exception 'Fuera de la edad Placeta Joven (16 a 31 años; el periodo de gracia termina el 31 de diciembre del año en que se cumplen 31)';
  end if;
  r:=plone27_joven_cuenta_crear(p_bank,p_dip,p_actor);
  per:=plone27_persona(p_dip);
  select jc.fecha_nacimiento into previa from plone27_joven_cuentas jc where jc.bank_id=p_bank and jc.persona=per;
  if previa is not null and previa<>p_nacimiento then raise exception 'La fecha de nacimiento no coincide con la registrada'; end if;
  update plone27_joven_cuentas set fecha_nacimiento=p_nacimiento where bank_id=p_bank and persona=per;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'joven_alta','persona',per::text,jsonb_build_object('verificada',true));
  return r || jsonb_build_object('nacimiento_verificada',true); end $$;

-- Congelación automática de las cuentas que dejan de ser elegibles (lo llama el proceso diario)
create or replace function plone27_joven_caducar_elegibilidad(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
declare n int; begin
  with x as(update plone27_joven_cuentas set congelada=true,
      congelada_motivo='Fuera de la edad Placeta Joven (16 a 31 años, con periodo de gracia hasta el 31 de diciembre del año en que se cumplen 31)',
      congelada_at=now()
    where fecha_nacimiento is not null and not plone27_joven_vigente(fecha_nacimiento) and not congelada returning 1)
  select count(*) into n from x;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'joven_elegibilidad','joven',null,jsonb_build_object('congeladas',n));
  return n; end $$;

-- Lectura: añade si la cuenta es elegible hoy (sin fecha de nacimiento, no lo es)
create or replace function plone27_joven_leer(p_iban text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare aid uuid; begin
  select a.id into aid from plone27_accounts a where a.iban=p_iban and a.kind='joven';
  if aid is null then return null; end if;
  return (select jsonb_build_object('iban',a.iban,'estado',a.status,'congelada',coalesce(jc.congelada,false),
      'motivo_congelacion',case when jc.congelada then jc.congelada_motivo end,
      'elegible',plone27_joven_vigente(jc.fecha_nacimiento),
      'disponible',plone27_available(a.id),'banco',b.name)
    from plone27_accounts a join plone27_banks b on b.id=a.bank_id left join plone27_joven_cuentas jc on jc.account_id=a.id
    where a.id=aid); end $$;

-- Congelar o descongelar. No se puede descongelar a quien ya no es elegible.
create or replace function plone27_joven_congelar(p_bank uuid,p_iban text,p_congelada boolean,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare aid uuid; begin
  if p_bank is distinct from plone27_banco_joven() then raise exception 'Solo Banco de La Placeta gestiona Placeta Joven'; end if;
  if p_congelada and coalesce(length(p_motivo),0)<10 then raise exception 'Para congelar, el motivo debe tener al menos 10 caracteres'; end if;
  select a.id into aid from plone27_accounts a where a.iban=p_iban and a.kind='joven' and a.bank_id=p_bank;
  if aid is null then raise exception 'Cuenta Placeta Joven no encontrada'; end if;
  if not p_congelada and exists(select 1 from plone27_joven_cuentas jc where jc.account_id=aid
       and jc.fecha_nacimiento is not null and not plone27_joven_vigente(jc.fecha_nacimiento)) then
    raise exception 'No se puede descongelar: la persona está fuera de la edad Placeta Joven';
  end if;
  update plone27_joven_cuentas set congelada=p_congelada,
    congelada_motivo=case when p_congelada then p_motivo end,
    congelada_at=case when p_congelada then now() end
    where account_id=aid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,case when p_congelada then 'joven_congelar' else 'joven_descongelar' end,'account',aid::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- Compra: exige elegibilidad hoy
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
  if not exists(select 1 from plone27_joven_cuentas jc where jc.account_id=j and plone27_joven_vigente(jc.fecha_nacimiento)) then
    raise exception 'Cuenta fuera de la edad Placeta Joven o sin fecha de nacimiento verificada';
  end if;
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

-- Recarga: exige elegibilidad hoy
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
  if not exists(select 1 from plone27_joven_cuentas jc where jc.account_id=j and plone27_joven_vigente(jc.fecha_nacimiento)) then
    raise exception 'Cuenta fuera de la edad Placeta Joven o sin fecha de nacimiento verificada';
  end if;
  perform set_config('plone27.joven_op','on',true);
  return plone27_transfer(p_clave,o,j,p_importe,coalesce(p_concepto,'Recarga Placeta Joven'),p_actor); end $$;

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

do $$ begin raise notice 'Actualización 0069 aplicada correctamente.'; end $$;

commit;
