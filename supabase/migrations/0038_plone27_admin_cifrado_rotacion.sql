-- Placeta One · 0038 · Cifrado de secretos de webhook, rotación de la clave de la pasarela de una empresa
-- y suspensión de empresas. Requiere 0037. Idempotente.

-- Marca de los secretos cifrados (los antiguos, en claro, se cifran al rotarlos)
alter table plone27_webhooks add column if not exists cifrado boolean generated always as (secret like 'enc:v1:%') stored;

-- Rotación de la clave de la pasarela de una empresa (solo un titular activo)
create or replace function plone27_empresa_pasarela_rotar(p_bank uuid,p_empresa uuid,p_key_hash text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank and e.estado='activa') then
    raise exception 'Empresa no encontrada o no activa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede rotar su clave';
  end if;
  select pe.client_id into cid from plone27_empresa_pasarelas pe where pe.empresa_id=p_empresa and pe.activa;
  if cid is null then raise exception 'La empresa no tiene pasarela activa'; end if;
  update plone27_api_clients set key_hash=p_key_hash where id=cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_clave_rotada','empresa',p_empresa::text,jsonb_build_object('client',cid));
  return cid; end $$;

-- Estado de la empresa. Suspender o dar de baja desactiva su pasarela; volver a activar la restaura.
create or replace function plone27_empresa_estado(p_bank uuid,p_empresa uuid,p_estado text,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  if p_estado not in('activa','suspendida','baja') then raise exception 'Estado no válido'; end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null)
     and p_actor is not null then
    raise exception 'Solo un titular de la empresa puede cambiar su estado';
  end if;
  with x as(update plone27_empresas set estado=p_estado where id=p_empresa and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Empresa no encontrada'; end if;
  update plone27_empresa_pasarelas pe set activa=(p_estado='activa') where pe.empresa_id=p_empresa;
  update plone27_api_clients c set active=(p_estado='activa')
    where c.id in(select pe.client_id from plone27_empresa_pasarelas pe where pe.empresa_id=p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_estado','empresa',p_empresa::text,jsonb_build_object('estado',p_estado,'motivo',p_motivo));
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
