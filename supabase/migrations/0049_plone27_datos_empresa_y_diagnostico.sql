-- Placeta One · 0049 · Identificador de empresa = CIP de la entidad. Vinculación automática por CIP.
-- En la plataforma no existe NIF para las entidades: el identificador de la empresa es el CIP.
-- Requiere 0048. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Si el identificador de la empresa es el CIP de una entidad activa de su mismo banco, se vincula sola
create or replace function plone27_empresa_autovincular(p_bank uuid,p_empresa uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; begin
  select * into e from plone27_empresas where id=p_empresa;
  if e.id is null or e.entidad_cip is not null then return; end if;
  select en.cip into v_cip from plone27_entidades en
    where en.cip=upper(e.identificador_fiscal) and en.bank_id=p_bank and en.activa;
  if v_cip is null then return; end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then return; end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'empresa_autovinculada','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
end $$;

-- Alta de empresa: intenta vincular la entidad por su identificador
create or replace function plone27_empresa_alta_completa(p_bank uuid,p_nombre text,p_fiscal text,p_persona uuid,p_ibans text[],p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare eid uuid; v_iban text; v_aid uuid; begin
  insert into plone27_empresas(bank_id,nombre,identificador_fiscal) values(p_bank,p_nombre,upper(p_fiscal))
    returning plone27_empresas.id into eid;
  foreach v_iban in array coalesce(p_ibans,'{}'::text[]) loop
    select a.id into v_aid from plone27_accounts a where a.iban=v_iban and a.bank_id=p_bank and a.kind='business' and a.status='active';
    if v_aid is null then raise exception 'La cuenta % no es una cuenta de empresa activa de tu entidad', v_iban; end if;
    insert into plone27_empresa_cuentas(empresa_id,account_id) values(eid,v_aid) on conflict do nothing;
  end loop;
  insert into plone27_empresa_titulares(empresa_id,persona,rol,motivo,alta_por)
    values(eid,p_persona,'titular','Alta de la empresa',p_actor);
  insert into plone27_account_members(account_id,user_id,role)
    select ec.account_id,p_persona,'holder' from plone27_empresa_cuentas ec where ec.empresa_id=eid on conflict do nothing;
  perform plone27_empresa_autovincular(p_bank,eid);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_alta','empresa',eid::text,jsonb_build_object('fiscal',upper(p_fiscal)));
  return eid; end $$;

-- La ficha muestra el vínculo con la entidad (entidad_cip)
create or replace function plone27_empresa_detalle(p_bank uuid,p_empresa uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb; begin
  select jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado,'entidad_cip',e.entidad_cip,
    'titulares',(select coalesce(jsonb_agg(jsonb_build_object('dip',p.dip,'rol',t.rol,'desde',t.desde,'hasta',t.hasta) order by t.desde),'[]'::jsonb)
                 from plone27_empresa_titulares t join plone27_personas p on p.id=t.persona where t.empresa_id=e.id),
    'cuentas',(select coalesce(jsonb_agg(jsonb_build_object('iban',a.iban,'nombre',a.name) order by a.iban),'[]'::jsonb)
               from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id where ec.empresa_id=e.id),
    'pasarela',(select jsonb_build_object('client_id',pe.client_id,'activa',pe.activa) from plone27_empresa_pasarelas pe where pe.empresa_id=e.id),
    'contrato_version',(select max(c.version) from plone27_empresa_contratos c where c.empresa_id=e.id))
  into r from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank;
  return r; end $$;

-- Corregir nombre e identificador (el identificador es el CIP de la entidad). Solo un titular activo.
create or replace function plone27_empresa_datos_set(p_bank uuid,p_empresa uuid,p_nombre text,p_fiscal text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede corregir sus datos';
  end if;
  if coalesce(length(p_nombre),0) not between 2 and 120 then raise exception 'Nombre entre 2 y 120 caracteres'; end if;
  if coalesce(length(p_fiscal),0) not between 5 and 20 then raise exception 'Identificador entre 5 y 20 caracteres'; end if;
  update plone27_empresas set nombre=p_nombre, identificador_fiscal=upper(p_fiscal) where id=p_empresa and bank_id=p_bank;
  if not found then raise exception 'Empresa no encontrada'; end if;
  perform plone27_empresa_autovincular(p_bank,p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_datos_set','empresa',p_empresa::text,jsonb_build_object('nombre',p_nombre));
end $$;

-- Empresas que ya tienen como identificador el CIP de una entidad de su banco: se vinculan ahora
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
