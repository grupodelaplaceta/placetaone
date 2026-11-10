-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0050 · Crear la entidad de una empresa; identificador = CIP nuevo
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0049.
-- ATENCIÓN: no ejecutada en PostgreSQL. Probar en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0050 · Crear la entidad de una empresa y hacer que su identificador sea el CIP nuevo.
-- Mensaje claro cuando el CIP indicado no existe en el banco. Requiere 0049. Idempotente. NO ejecutado en PostgreSQL.

create or replace function plone27_empresa_vincular_entidad(p_bank uuid,p_empresa uuid,p_cip text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  if not exists(select 1 from plone27_entidades x where x.cip=upper(p_cip) and x.bank_id=p_bank and x.activa) then
    raise exception 'La entidad % no existe o está inactiva en tu banco. Si no tienes entidad, créala sobre una cuenta de la empresa', p_cip;
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=upper(p_cip) and o.id<>p_empresa) then
    raise exception 'Esa entidad ya está vinculada a otra empresa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede vincular una entidad';
  end if;
  update plone27_empresas set entidad_cip=upper(p_cip), identificador_fiscal=upper(p_cip) where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_vincular_entidad','empresa',p_empresa::text,jsonb_build_object('cip',p_cip));
end $$;

create or replace function plone27_empresa_crear_entidad(p_bank uuid,p_empresa uuid,p_iban text,p_nombre text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; v_nombre text; begin
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
  v_nombre:=coalesce(nullif(p_nombre,''),e.nombre);
  select x.cip into v_cip from plone27_entidades x where x.account_id=v_aid;
  if v_cip is null then
    v_cip:=plone27_entidad_alta(p_bank,v_aid,v_nombre,p_actor);
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then
    raise exception 'Esa entidad ya está vinculada a otra empresa';
  end if;
  update plone27_empresas set entidad_cip=v_cip, identificador_fiscal=v_cip where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_crear_entidad','empresa',p_empresa::text,jsonb_build_object('cip',v_cip,'cuenta',v_aid));
  return v_cip; end $$;


do $$ begin raise notice 'Actualización 0050 aplicada correctamente.'; end $$;

commit;
