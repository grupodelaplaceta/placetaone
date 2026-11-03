-- Placeta One · 0020 · Mantenimiento de la API de bancos y gestión de orígenes de navegador desde el panel.
-- Requiere 0019. Idempotente.

-- Quitar un origen de navegador de un cliente
create or replace function plone27_client_origin_remove(p_client uuid,p_origin text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$ begin
  delete from plone27_client_origins where client_id=p_client and origin=p_origin;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'client_origin_remove','client',p_client::text,jsonb_build_object('origen',p_origin));
end $$;

-- Limpieza diaria: nonces de más de un día (la ventana de firma es de 5 minutos)
-- y sesiones caducadas hace más de 30 días. Las sesiones recientes se conservan para auditoría.
create or replace function plone27_limpiar_api() returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n1 int; n2 int; begin
  with x as(delete from plone27_api_nonces where at<now()-interval '1 day' returning 1) select count(*) into n1 from x;
  with y as(delete from plone27_user_sessions where expires_at<now()-interval '30 days' returning 1) select count(*) into n2 from y;
  return jsonb_build_object('nonces_borrados',n1,'sesiones_borradas',n2); end $$;

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
