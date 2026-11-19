-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0052 · La empresa es su entidad institucional (automática)
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0051.
-- ATENCIÓN: no ejecutada en PostgreSQL. Probar en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0052 · La empresa es su entidad institucional: se crea automáticamente al añadir su primera cuenta de empresa.
-- Requiere 0051. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Garantiza la entidad de la empresa: reutiliza la que ya exista en una de sus cuentas, o la crea sobre la primera cuenta de empresa
create or replace function plone27_empresa_asegurar_entidad(p_empresa uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; v_aid uuid; begin
  select * into e from plone27_empresas where id=p_empresa for update;
  if e.id is null then return null; end if;
  if e.entidad_cip is not null then return e.entidad_cip; end if;
  select en.cip into v_cip from plone27_empresa_cuentas ec
    join plone27_entidades en on en.account_id=ec.account_id
    where ec.empresa_id=p_empresa and en.bank_id=e.bank_id and en.activa limit 1;
  if v_cip is null then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status='active' and a.kind='business' order by a.created_at limit 1;
    if v_aid is null then return null; end if;
    v_cip:=plone27_entidad_alta(e.bank_id,v_aid,e.nombre,p_actor);
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then return null; end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=e.bank_id and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_entidad_automatica','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
  return v_cip; end $$;

-- Cada cuenta nueva de empresa asegura la entidad de la empresa
create or replace function plone27_trg_empresa_cuentas_entidad() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  perform plone27_empresa_asegurar_entidad(new.empresa_id,null);
  return new; end $$;
drop trigger if exists trg_empresa_cuentas_entidad on plone27_empresa_cuentas;
drop trigger if exists trg_empresa_cuentas_entidad on plone27_empresa_cuentas;
create trigger trg_empresa_cuentas_entidad after insert on plone27_empresa_cuentas
  for each row execute function plone27_trg_empresa_cuentas_entidad();

-- Empresas existentes con cuentas y sin entidad: se resuelven ahora
do $$ declare r record; begin
  for r in select id from plone27_empresas where entidad_cip is null loop
    perform plone27_empresa_asegurar_entidad(r.id,null);
  end loop;
end $$;

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


do $$ begin raise notice 'Actualización 0052 aplicada correctamente.'; end $$;

commit;
