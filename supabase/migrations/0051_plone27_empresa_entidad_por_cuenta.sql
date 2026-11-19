-- Placeta One · 0051 · Empresa y entidad son lo mismo: si una cuenta de la empresa ya es una entidad del banco, se vincula.
-- Crear la entidad reutiliza la existente. Mensajes que dicen qué empresa ya tiene la entidad. Requiere 0050. Idempotente.

-- Vinculación automática: por identificador (CIP) o por cuenta de la empresa que ya es una entidad
create or replace function plone27_empresa_autovincular(p_bank uuid,p_empresa uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; begin
  select * into e from plone27_empresas where id=p_empresa;
  if e.id is null or e.entidad_cip is not null then return; end if;
  select en.cip into v_cip from plone27_entidades en
    where en.cip=upper(e.identificador_fiscal) and en.bank_id=p_bank and en.activa;
  if v_cip is null then
    select en.cip into v_cip from plone27_empresa_cuentas ec
      join plone27_entidades en on en.account_id=ec.account_id
      where ec.empresa_id=p_empresa and en.bank_id=p_bank and en.activa limit 1;
  end if;
  if v_cip is null then return; end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then return; end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=p_bank and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'empresa_autovinculada','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
end $$;

-- Crear la entidad de la empresa: reutiliza la entidad que ya exista en esa cuenta
create or replace function plone27_empresa_crear_entidad(p_bank uuid,p_empresa uuid,p_iban text,p_nombre text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; v_nombre text; v_activa boolean; v_otra text; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank for update;
  if e.id is null or e.estado<>'activa' then raise exception 'Empresa no encontrada o no activa'; end if;
  if e.entidad_cip is not null then raise exception 'La empresa ya tiene una entidad vinculada (%)', e.entidad_cip; end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede crear su entidad';
  end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.iban=p_iban;
    if v_aid is null then raise exception 'La cuenta no pertenece a esta empresa'; end if;
  else
    select ec.account_id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status='active' order by a.created_at limit 1;
    if v_aid is null then raise exception 'La empresa no tiene cuentas de empresa'; end if;
  end if;
  -- ¿La cuenta ya es una entidad? Se reutiliza.
  select x.cip, x.activa into v_cip, v_activa from plone27_entidades x where x.account_id=v_aid and x.bank_id=p_bank;
  if v_cip is null then
    v_nombre:=coalesce(nullif(p_nombre,''),e.nombre);
    v_cip:=plone27_entidad_alta(p_bank,v_aid,v_nombre,p_actor);
  elsif not v_activa then
    raise exception 'La entidad % de esa cuenta está inactiva en tu banco', v_cip;
  end if;
  select o.nombre into v_otra from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa;
  if v_otra is not null then
    raise exception 'La entidad % ya está vinculada a la empresa "%"', v_cip, v_otra;
  end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=p_bank and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_crear_entidad','empresa',p_empresa::text,jsonb_build_object('cip',v_cip,'cuenta',v_aid));
  return v_cip; end $$;

-- Empresas existentes: se vinculan ahora si su cuenta ya es una entidad del banco
do $$ declare r record; begin
  for r in select e.id, e.bank_id from plone27_empresas e where e.entidad_cip is null loop
    perform plone27_empresa_autovincular(r.bank_id, r.id);
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
