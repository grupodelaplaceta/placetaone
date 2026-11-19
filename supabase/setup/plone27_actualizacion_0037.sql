-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0037 · Tasas de pasarela, operaciones interbancarias y posición neta
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0036.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0037 · Tasas configurables para pasarelas (por banco, por pasarela y por medio de pago),
-- aplicación automática al cobrar, operaciones interbancarias y posición neta frente a cada banco.
-- Requiere 0036. Idempotente.

-- ---------- Catálogo de tasas ----------
create table if not exists plone27_tasas(
  id uuid primary key default gen_random_uuid(),
  ambito text not null check(ambito in('propietario','banco')),
  bank_id uuid not null references plone27_banks,
  client_id uuid references plone27_api_clients,
  operacion text not null default 'pasarela_pago' check(operacion in('pasarela_pago')),
  medio text check(medio is null or medio in('cuenta','tarjeta')),
  tipo text not null check(tipo in('fijo','porcentaje')),
  valor numeric(18,4) not null check(valor>=0),
  minimo numeric(18,2) not null default 0 check(minimo>=0),
  maximo numeric(18,2) check(maximo is null or maximo>=minimo),
  pagador text not null check(pagador in('comercio','banco')),
  beneficiario text not null check(beneficiario in('propietario','banco')),
  activa boolean not null default true,
  creada timestamptz not null default now(),
  check(ambito='propietario' or (beneficiario='banco' and pagador='comercio')));

-- Registro de cada tasa cobrada (idempotente por pago y tasa)
create table if not exists plone27_tasas_cobradas(
  checkout uuid not null references plone27_checkouts(id),
  tasa uuid not null references plone27_tasas(id),
  importe numeric(18,2) not null check(importe>0),
  pagador text not null,
  beneficiario text not null,
  tx uuid,
  creada timestamptz not null default now(),
  primary key(checkout,tasa));

-- Tasas que aplican a un pago de la pasarela (importe calculado y acotado por mínimo y máximo)
create or replace function plone27_tasas_aplicables(p_bank uuid,p_client uuid,p_medio text,p_importe numeric)
returns table(tasa uuid,pagador text,beneficiario text,importe numeric)
language sql stable security definer set search_path=public as $$
  select t.id, t.pagador, t.beneficiario,
    round(least(greatest(case when t.tipo='fijo' then t.valor else p_importe*t.valor/100 end, t.minimo),
      coalesce(t.maximo,999999999999)),2)
  from plone27_tasas t
  where t.activa and t.bank_id=p_bank and t.operacion='pasarela_pago'
    and (t.medio is null or t.medio=p_medio)
    and (t.client_id is null or t.client_id=p_client) $$;

-- Cobro automático de las tasas cuando un pago de la pasarela queda pagado
create or replace function plone27_trg_tasas_pasarela() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t record; orig uuid; ben uuid; tx uuid; begin
  for t in select x.tasa, x.pagador, x.beneficiario, x.importe from plone27_tasas_aplicables(new.bank_id,new.client_id,new.medio,new.importe) x loop
    if t.importe<=0 then continue; end if;
    orig:=case when t.pagador='comercio' then new.cuenta_destino else plone27_comision_cuenta(new.bank_id) end;
    ben:=case when t.beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(new.bank_id) end;
    if orig=ben then continue; end if;
    tx:=plone27_transfer('tasa:'||new.id::text||':'||t.tasa::text,orig,ben,t.importe,'Tasa de pasarela',null);
    insert into plone27_tasas_cobradas(checkout,tasa,importe,pagador,beneficiario,tx)
      values(new.id,t.tasa,t.importe,t.pagador,t.beneficiario,tx) on conflict(checkout,tasa) do nothing;
  end loop;
  return new; end $$;
drop trigger if exists trg_tasas_pasarela on plone27_checkouts;
drop trigger if exists trg_tasas_pasarela on plone27_checkouts;
create trigger trg_tasas_pasarela after update of estado on plone27_checkouts
  for each row when (new.estado='pagado' and old.estado is distinct from 'pagado')
  execute function plone27_trg_tasas_pasarela();

-- ---------- Alta y baja de tasas ----------
-- La administración (ámbito propietario) puede fijar cualquier tasa; el banco solo las suyas, que cobra él a sus comercios.
create or replace function plone27_tasa_alta(p_bank uuid,p_ambito text,p_client uuid,p_medio text,p_tipo text,p_valor numeric,
    p_minimo numeric,p_maximo numeric,p_pagador text,p_beneficiario text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare tid uuid; begin
  if not exists(select 1 from plone27_banks b where b.id=p_bank and b.active) then raise exception 'Entidad no encontrada'; end if;
  if p_client is not null and not exists(select 1 from plone27_api_clients c where c.id=p_client and c.bank_id=p_bank) then
    raise exception 'El cliente no pertenece a la entidad';
  end if;
  if p_ambito='banco' and (p_pagador<>'comercio' or p_beneficiario<>'banco') then
    raise exception 'La entidad solo puede cobrar tasas a sus comercios para su propio beneficio';
  end if;
  insert into plone27_tasas(ambito,bank_id,client_id,medio,tipo,valor,minimo,maximo,pagador,beneficiario)
    values(p_ambito,p_bank,p_client,p_medio,p_tipo,p_valor,coalesce(p_minimo,0),p_maximo,p_pagador,p_beneficiario)
    returning plone27_tasas.id into tid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tasa_alta','bank',p_bank::text,jsonb_build_object('tasa',tid,'ambito',p_ambito,'valor',p_valor,'tipo',p_tipo));
  return tid; end $$;

create or replace function plone27_tasa_desactivar(p_bank uuid,p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_tasas set activa=false where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Tasa no encontrada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tasa_desactivar','bank',p_bank::text,jsonb_build_object('tasa',p_id));
end $$;

create or replace function plone27_tasas_listar(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select t.id, t.ambito, t.client_id, t.medio, t.tipo, t.valor, t.minimo, t.maximo, t.pagador, t.beneficiario, t.activa, t.creada
    from plone27_tasas t where t.bank_id=p_bank) x $$;

-- ---------- Operaciones interbancarias de la entidad ----------
create or replace function plone27_interbancarias(p_bank uuid,p_desde date,p_hasta date) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select c.id, c.client_ref as referencia, c.estado, c.importe, c.comision, c.comision_pagador, c.creada,
      case when c.banco_pagador=p_bank then 'pagada' else 'cobrada' end as sentido,
      (select b.code from plone27_accounts a join plone27_banks b on b.id=a.bank_id where a.id=c.cuenta_destino) as banco_destino
    from plone27_checkouts c
    where c.interbancaria and (c.banco_pagador=p_bank or c.bank_id=p_bank)
      and c.creada::date between p_desde and p_hasta) x $$;

-- Posición neta de la entidad frente a cada banco con operaciones pagadas en el periodo
create or replace function plone27_posicion_interbancaria(p_bank uuid,p_desde date,p_hasta date) returns jsonb
language sql stable security definer set search_path=public as $$
  with ops as(
    select c.banco_pagador as origen, a.bank_id as destino, c.importe
    from plone27_checkouts c join plone27_accounts a on a.id=c.cuenta_destino
    where c.estado='pagado' and c.interbancaria and c.resuelta::date between p_desde and p_hasta),
  contra as(
    select distinct case when o.origen=p_bank then o.destino else o.origen end as banco
    from ops o where p_bank in(o.origen,o.destino) and o.origen<>o.destino)
  select coalesce(jsonb_agg(to_jsonb(x) order by x.banco_codigo),'[]'::jsonb) from (
    select b.code as banco_codigo, b.name as banco,
      coalesce((select sum(o.importe) from ops o where o.origen=p_bank and o.destino=ct.banco),0) as enviado,
      coalesce((select sum(o.importe) from ops o where o.origen=ct.banco and o.destino=p_bank),0) as recibido,
      coalesce((select sum(o.importe) from ops o where o.origen=ct.banco and o.destino=p_bank),0)
        -coalesce((select sum(o.importe) from ops o where o.origen=p_bank and o.destino=ct.banco),0) as neto
    from contra ct join plone27_banks b on b.id=ct.banco) x $$;

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


do $$ begin raise notice 'Actualización 0037 aplicada correctamente.'; end $$;

commit;
