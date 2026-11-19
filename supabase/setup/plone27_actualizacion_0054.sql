-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0054 · Entidades de empresa automáticas (disparador + cron cada 15 minutos)
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0053.
-- ATENCIÓN: no ejecutada en PostgreSQL. Probar en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0054 · La entidad de cada empresa se crea y se repara sola (disparador + cron cada 15 minutos).
-- Los errores quedan en la auditoría y se muestran en la ficha. Requiere 0053. Idempotente. NO ejecutado en PostgreSQL.

-- Repara todas las empresas activas con cuentas y sin entidad. Devuelve cuántas ha resuelto.
create or replace function plone27_empresa_reparar_entidades() returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; n int:=0; begin
  for r in select e.id from plone27_empresas e
           where e.entidad_cip is null and e.estado='activa'
             and exists(select 1 from plone27_empresa_cuentas ec where ec.empresa_id=e.id) loop
    begin
      if plone27_empresa_asegurar_entidad(r.id,null) is not null then n:=n+1; end if;
    exception when others then
      insert into plone27_audit_log(actor,action,entity,entity_id,detail)
        values(null,'empresa_entidad_pendiente','empresa',r.id::text,jsonb_build_object('error',sqlerrm));
    end;
  end loop;
  return n; end $$;

-- Pasada inicial sobre lo que ya existe
do $$ begin perform plone27_empresa_reparar_entidades(); end $$;

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


do $$ begin raise notice 'Actualización 0054 aplicada correctamente.'; end $$;

commit;
