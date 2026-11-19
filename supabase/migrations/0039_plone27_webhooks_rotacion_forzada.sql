-- Placeta One · 0039 · Rotación forzada de secretos de webhook sin cifrar.
-- Desactiva los webhooks con secreto en claro; al rotarlos, el banco vuelve a quedar activo con secreto cifrado.
-- Requiere 0038. Idempotente.

create or replace function plone27_bk_webhook_rotar(p_bank uuid,p_id uuid,p_secret text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_webhooks set secret=p_secret, active=true where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Webhook no encontrado'; end if;
end $$;

create or replace function plone27_webhooks_desactivar_sin_cifrar(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_webhooks set active=false where active and secret not like 'enc:v1:%' returning 1)
  select count(*) into n from x;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'webhooks_desactivados_sin_cifrar','webhook',null,jsonb_build_object('n',n));
  return n; end $$;

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
