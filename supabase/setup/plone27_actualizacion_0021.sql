-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0021 · Orígenes de navegador (CORS) gestionados por el banco
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0020.
-- AÑADE: solicitud de orígenes por el banco (pendientes de aprobación), aprobación por el personal,
--        y CORS que solo acepta orígenes aprobados de su propio cliente.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0021 · Orígenes de navegador (CORS) gestionados por el banco, con aprobación del personal.
-- Requiere 0020. Idempotente.

alter table plone27_client_origins add column if not exists estado text not null default 'aprobado'
  check(estado in('pendiente','aprobado','rechazado'));   -- los orígenes existentes quedan aprobados
alter table plone27_client_origins add column if not exists entorno text not null default 'produccion'
  check(entorno in('produccion','pruebas'));
alter table plone27_client_origins add column if not exists solicitado_at timestamptz not null default now();
alter table plone27_client_origins add column if not exists aprobado_por uuid;
alter table plone27_client_origins add column if not exists aprobado_at timestamptz;

-- Formato permitido. Producción: https://dominio[:puerto], sin ruta, sin comodines.
-- Pruebas: además http://localhost[:puerto].
create or replace function plone27_origen_valido(p_origin text,p_entorno text) returns boolean
language sql immutable as $$
  select case when p_entorno='pruebas'
    then p_origin ~ '^https://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]{1,5})?$' or p_origin ~ '^http://localhost(:[0-9]{1,5})?$'
    else p_origin ~ '^https://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]{1,5})?$'
  end $$;

-- El banco solicita un origen: queda pendiente. Máximo 10 por cliente.
create or replace function plone27_client_origin_request(p_client uuid,p_origin text,p_entorno text) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare o text:=lower(trim(p_origin)); n int; est text; begin
  if p_entorno not in('produccion','pruebas') then raise exception 'Entorno no válido'; end if;
  if not plone27_origen_valido(o,p_entorno) then raise exception 'Origen no válido: https://dominio[:puerto], sin ruta ni comodines'; end if;
  select count(*) into n from plone27_client_origins where client_id=p_client and estado<>'rechazado';
  if n>=10 then raise exception 'Máximo 10 orígenes por cliente'; end if;
  insert into plone27_client_origins(client_id,origin,estado,entorno,solicitado_at)
    values(p_client,o,'pendiente',p_entorno,now())
    on conflict(client_id,origin) do update
      set estado=case when plone27_client_origins.estado='rechazado' then 'pendiente' else plone27_client_origins.estado end,
          entorno=excluded.entorno
    returning plone27_client_origins.estado into est;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'client_origin_request','client',p_client::text,jsonb_build_object('origen',o,'entorno',p_entorno,'estado',est));
  return est; end $$;

-- El personal aprueba o rechaza
create or replace function plone27_client_origin_decide(p_client uuid,p_origin text,p_decision text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_decision not in('aprobado','rechazado') then raise exception 'Decisión no válida'; end if;
  if p_actor is null then raise exception 'La decisión requiere un aprobador'; end if;
  update plone27_client_origins set estado=p_decision,aprobado_por=p_actor,aprobado_at=now()
    where client_id=p_client and origin=lower(trim(p_origin));
  if not found then raise exception 'Origen no encontrado'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'client_origin_decide','client',p_client::text,jsonb_build_object('origen',lower(trim(p_origin)),'decision',p_decision));
end $$;

-- Lista de orígenes de un cliente (lo consulta el propio banco)
create or replace function plone27_client_origins_list(p_client uuid)
returns table(origin text,estado text,entorno text,solicitado timestamptz,aprobado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select o.origin,o.estado,o.entorno,o.solicitado_at,o.aprobado_at
    from plone27_client_origins o where o.client_id=p_client order by o.origin;
end $$;

-- ¿Puede este origen llamar a la API? Solo si está aprobado y su cliente activo.
-- Con p_client se comprueba que el origen pertenece a ese cliente concreto.
create or replace function plone27_origen_permitido(p_origin text,p_client uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_client_origins o join plone27_api_clients c on c.id=o.client_id
    where o.origin=lower(p_origin) and o.estado='aprobado' and c.active
      and (p_client is null or o.client_id=p_client)) $$;

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


do $$ begin raise notice 'Actualización 0021 aplicada correctamente.'; end $$;

commit;
