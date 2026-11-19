-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0035 · Entregas de webhook con fechas e intentos, y reintento manual
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0034.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0035 · Entregas de webhook con fechas e intentos, y reintento manual.
-- Un reintento devuelve el evento fallido a pendiente y pone sus intentos a cero; el envío automático lo vuelve a intentar.
-- Requiere 0034. Idempotente.

create or replace function plone27_bk_entrega_reintentar(p_bank uuid,p_id bigint) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_outbox set status='pending', attempts=0
            where id=p_id and status='failed' and p_bank=any(bank_ids) returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'La entrega no existe, no es de tu entidad o no está fallida'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'webhook_reintento','outbox',p_id::text,jsonb_build_object('bank',p_bank));
end $$;

create or replace function plone27_bk_entregas_lista(p_bank uuid,p_estado text,p_limite int) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc),'[]'::jsonb) from (
    select o.id, o.event as evento, o.status as estado, o.attempts as intentos, o.created_at as creada,
      coalesce(o.payload->>'checkout_id', o.payload->>'gasto', o.payload->>'tarea', o.payload->>'operation', o.payload->>'periodo') as referencia
    from plone27_outbox o
    where p_bank=any(o.bank_ids) and (p_estado is null or o.status=p_estado)
    order by o.id desc limit least(greatest(coalesce(p_limite,50),1),200)) x $$;

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


do $$ begin raise notice 'Actualización 0035 aplicada correctamente.'; end $$;

commit;
