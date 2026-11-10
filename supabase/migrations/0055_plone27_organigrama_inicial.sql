-- Placeta One · 0055 · La entidad de cada empresa nace con su organigrama inicial: unidad raíz, puesto de titular
-- con todos los permisos y nombramiento del titular de la empresa. Sin esto nadie puede cambiar el organigrama (422).
-- Requiere 0054. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Crea la unidad raíz, el puesto de titular y el nombramiento, solo si la entidad aún no tiene unidades
create or replace function plone27_empresa_bootstrap_organigrama(p_empresa uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; ent plone27_entidades; per uuid; uid uuid; pid uuid; acc text; begin
  select * into e from plone27_empresas where id=p_empresa;
  if e.id is null or e.entidad_cip is null then return; end if;
  select * into ent from plone27_entidades where cip=e.entidad_cip;
  if ent.account_id is null then return; end if;
  if exists(select 1 from plone27_unidades u where u.entidad=ent.account_id) then return; end if;
  select t.persona into per from plone27_empresa_titulares t
    where t.empresa_id=p_empresa and t.rol='titular' and t.hasta is null order by t.desde limit 1;
  if per is null then return; end if;
  uid:=plone27_unidad_alta(ent.account_id,'junta',null,ent.nombre,null,null);
  pid:=plone27_puesto_alta(uid,'Titular',5,null);
  foreach acc in array array['proponer','aprobar','ejecutar','presupuestar','reasignar','retribuir','organigrama','cerrar'] loop
    insert into plone27_puesto_permisos(puesto,accion) values(pid,acc) on conflict do nothing;
  end loop;
  perform plone27_nombrar(pid,per,'Titular de la empresa (organigrama inicial)',null);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'organigrama_inicial','empresa',p_empresa::text,jsonb_build_object('unidad',uid,'puesto',pid));
end $$;

-- Al crear o asegurar la entidad de una cuenta de empresa: se deja el organigrama inicial
create or replace function plone27_trg_empresa_cuentas_entidad() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  begin
    perform plone27_empresa_asegurar_entidad(new.empresa_id,null);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_entidad_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  begin
    perform plone27_empresa_bootstrap_organigrama(new.empresa_id);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_organigrama_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  return new; end $$;

-- Al dar de alta un titular: si la entidad aún no tiene organigrama, se crea con él como titular
create or replace function plone27_trg_empresa_titular_organigrama() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  begin
    perform plone27_empresa_bootstrap_organigrama(new.empresa_id);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_organigrama_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  return new; end $$;
drop trigger if exists trg_empresa_titular_organigrama on plone27_empresa_titulares;
create trigger trg_empresa_titular_organigrama after insert on plone27_empresa_titulares
  for each row execute function plone27_trg_empresa_titular_organigrama();

-- Añadir una cuenta: también deja el organigrama inicial
create or replace function plone27_empresa_cuenta_anadir(p_bank uuid,p_empresa uuid,p_iban text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null or e.estado<>'activa' then raise exception 'Empresa no encontrada o no activa'; end if;
  if p_actor is not null and not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede añadir cuentas';
  end if;
  select a.id into v_aid from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if v_aid is null then raise exception 'La cuenta % no existe en tu banco', p_iban; end if;
  insert into plone27_empresa_cuentas(empresa_id,account_id) values(p_empresa,v_aid) on conflict do nothing;
  insert into plone27_account_members(account_id,user_id,role)
    select v_aid, t.persona, case t.rol when 'titular' then 'holder' when 'autorizado' then 'coholder' else 'authorized' end
    from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.hasta is null
    on conflict do nothing;
  v_cip:=plone27_empresa_asegurar_entidad(p_empresa,p_actor);
  begin
    perform plone27_empresa_bootstrap_organigrama(p_empresa);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_organigrama_pendiente','empresa',p_empresa::text,jsonb_build_object('error',sqlerrm));
  end;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_cuenta_anadir','empresa',p_empresa::text,jsonb_build_object('iban',p_iban));
  return v_cip; end $$;

-- Empresas existentes con entidad y titular: se completa su organigrama inicial
do $$ declare r record; begin
  for r in select id from plone27_empresas where entidad_cip is not null loop
    begin
      perform plone27_empresa_bootstrap_organigrama(r.id);
    exception when others then
      insert into plone27_audit_log(actor,action,entity,entity_id,detail)
        values(null,'empresa_organigrama_pendiente','empresa',r.id::text,jsonb_build_object('error',sqlerrm));
    end;
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
