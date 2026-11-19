-- Placeta One · 0053 · Añadir cuentas a la empresa y crear su entidad de forma explícita.
-- La creación automática no hace fallar el alta: si no puede, deja constancia y el botón la fuerza. Requiere 0052. Idempotente.

-- Garantiza la entidad: reutiliza la que ya exista en una cuenta de la empresa, o la crea sobre la mejor cuenta disponible
create or replace function plone27_empresa_asegurar_entidad(p_empresa uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; v_aid uuid; v_act boolean; begin
  select * into e from plone27_empresas where id=p_empresa for update;
  if e.id is null then return null; end if;
  if e.entidad_cip is not null then return e.entidad_cip; end if;
  select en.cip into v_cip from plone27_empresa_cuentas ec join plone27_entidades en on en.account_id=ec.account_id
    where ec.empresa_id=p_empresa and en.bank_id=e.bank_id and en.activa limit 1;
  if v_cip is null then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status is distinct from 'closed'
      order by (a.kind='business') desc, (a.status='active') desc, a.created_at limit 1;
    if v_aid is null then return null; end if;
    select x.cip, x.activa into v_cip, v_act from plone27_entidades x where x.account_id=v_aid;
    if v_cip is not null and not v_act then raise exception 'La entidad % de esa cuenta está inactiva', v_cip; end if;
    if v_cip is null then v_cip:=plone27_entidad_alta(e.bank_id,v_aid,e.nombre,p_actor); end if;
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then
    raise exception 'La entidad % ya está vinculada a otra empresa', v_cip;
  end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=e.bank_id and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_entidad','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
  return v_cip; end $$;

-- Al insertar una cuenta de empresa se intenta asegurar la entidad; si falla, no se bloquea el alta
create or replace function plone27_trg_empresa_cuentas_entidad() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  begin
    perform plone27_empresa_asegurar_entidad(new.empresa_id,null);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_entidad_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  return new; end $$;

-- Añadir una cuenta a la empresa: da permisos a sus titulares y asegura la entidad
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
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_cuenta_anadir','empresa',p_empresa::text,jsonb_build_object('iban',p_iban));
  return v_cip; end $$;

-- Empresas existentes sin entidad: se resuelven ahora
do $$ declare r record; begin
  for r in select id from plone27_empresas where entidad_cip is null loop
    begin
      perform plone27_empresa_asegurar_entidad(r.id,null);
    exception when others then
      insert into plone27_audit_log(actor,action,entity,entity_id,detail)
        values(null,'empresa_entidad_pendiente','empresa',r.id::text,jsonb_build_object('error',sqlerrm));
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
