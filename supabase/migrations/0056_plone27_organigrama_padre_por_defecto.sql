-- Placeta One · 0056 · Una unidad sin padre se cuelga automáticamente de la Junta raíz de la entidad.
-- Antes, crear un departamento sin padre respondía 422 "Una unidad de tipo necesita una unidad padre".
-- Requiere 0055. Idempotente. NO ejecutado en PostgreSQL.

create or replace function plone27_org_unidad_nueva(p_bank uuid,p_cip text,p_actor uuid,p_tipo text,p_padre uuid,p_nombre text,p_codigo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if p_padre is null and p_tipo<>'junta' then
    select u.id into p_padre from plone27_unidades u
      where u.entidad=ent and u.activa and u.padre is null order by u.creada limit 1;
  end if;
  if p_padre is not null and not exists(select 1 from plone27_unidades u where u.id=p_padre and u.entidad=ent and u.activa) then
    raise exception 'Unidad superior no válida o cerrada';
  end if;
  return plone27_unidad_alta(ent,p_tipo,p_padre,p_nombre,p_codigo,p_actor); end $$;

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
