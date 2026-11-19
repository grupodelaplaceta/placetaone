-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0036 · Empresas, titulares, pasarela por empresa, contratos y NFC de tarjetas
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0035.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0036 · Empresas (titulares y cuentas), pasarela por empresa con su propio cliente de API,
-- contratos versionados y identificadores NFC de tarjetas. Requiere 0035. Idempotente.

-- ---------- Empresas ----------
create table if not exists plone27_empresas(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks,
  nombre text not null check(length(nombre) between 2 and 120),
  identificador_fiscal text not null check(length(identificador_fiscal) between 5 and 20),
  estado text not null default 'activa' check(estado in('activa','suspendida','baja')),
  creada timestamptz not null default now(),
  unique(bank_id,identificador_fiscal));

create table if not exists plone27_empresa_cuentas(
  empresa_id uuid not null references plone27_empresas(id),
  account_id uuid not null references plone27_accounts,
  primary key(empresa_id,account_id));

create table if not exists plone27_empresa_titulares(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references plone27_empresas(id),
  persona uuid not null references plone27_personas,
  rol text not null check(rol in('titular','autorizado','lector')),
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  alta_por uuid,
  check(hasta is null or hasta>=desde));
create unique index if not exists plone27_empresa_titular_activo_ux on plone27_empresa_titulares(empresa_id,persona) where hasta is null;

-- ---------- Pasarela de la empresa: un cliente de API propio ----------
create table if not exists plone27_empresa_pasarelas(
  empresa_id uuid primary key references plone27_empresas(id),
  client_id uuid not null unique references plone27_api_clients,
  activa boolean not null default true,
  creada timestamptz not null default now());

-- ---------- Contratos versionados (sin claves) ----------
create table if not exists plone27_empresa_contratos(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references plone27_empresas(id),
  version int not null check(version>=1),
  texto text not null check(length(texto)<=20000),
  creado timestamptz not null default now(),
  unique(empresa_id,version));

-- ---------- NFC de tarjetas (físicas o virtuales) ----------
alter table plone27_cards add column if not exists nfc_id text check(nfc_id is null or nfc_id ~ '^[A-Za-z0-9:_-]{8,64}$');
alter table plone27_cards add column if not exists nfc_enlace text check(nfc_enlace is null or nfc_enlace ~ '^https://[^\s]+$');
alter table plone27_cards add column if not exists nfc_actualizado timestamptz;
create unique index if not exists plone27_cards_nfc_id_ux on plone27_cards(nfc_id);

-- ---------- Las empresas solo cobran a sus propias cuentas (regla de base de datos) ----------
create or replace function plone27_trg_checkout_empresa() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare emp uuid; begin
  select pe.empresa_id into emp from plone27_empresa_pasarelas pe where pe.client_id=new.client_id and pe.activa;
  if emp is not null and not exists(select 1 from plone27_empresa_cuentas ec where ec.empresa_id=emp and ec.account_id=new.cuenta_destino) then
    raise exception 'Esta pasarela solo cobra a las cuentas de su empresa';
  end if;
  return new; end $$;
drop trigger if exists trg_checkout_empresa on plone27_checkouts;
drop trigger if exists trg_checkout_empresa on plone27_checkouts;
create trigger trg_checkout_empresa before insert on plone27_checkouts
  for each row execute function plone27_trg_checkout_empresa();

-- ---------- Funciones de gestión ----------
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
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_alta','empresa',eid::text,jsonb_build_object('fiscal',upper(p_fiscal)));
  return eid; end $$;

create or replace function plone27_empresa_titular_alta(p_bank uuid,p_empresa uuid,p_persona uuid,p_rol text,p_motivo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare tid uuid; activos int; mrole text; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank and e.estado='activa') then
    raise exception 'Empresa no encontrada o no activa';
  end if;
  if p_rol not in('titular','autorizado','lector') then raise exception 'Rol no válido'; end if;
  select count(*) into activos from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.rol='titular' and t.hasta is null;
  if activos>0 and not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede dar altas';
  end if;
  insert into plone27_empresa_titulares(empresa_id,persona,rol,motivo,alta_por)
    values(p_empresa,p_persona,p_rol,p_motivo,p_actor) returning plone27_empresa_titulares.id into tid;
  mrole:=case p_rol when 'titular' then 'holder' when 'autorizado' then 'coholder' else 'authorized' end;
  insert into plone27_account_members(account_id,user_id,role)
    select ec.account_id,p_persona,mrole from plone27_empresa_cuentas ec where ec.empresa_id=p_empresa on conflict do nothing;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_titular_alta','empresa',p_empresa::text,jsonb_build_object('rol',p_rol));
  return tid; end $$;

create or replace function plone27_empresa_titular_cese(p_bank uuid,p_empresa uuid,p_persona uuid,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare activos int; n int; era_titular boolean; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank) then raise exception 'Empresa no encontrada'; end if;
  select count(*) into activos from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.rol='titular' and t.hasta is null;
  era_titular:=exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_persona and t.rol='titular' and t.hasta is null);
  if era_titular and activos<=1 then raise exception 'La empresa necesita al menos un titular'; end if;
  with x as(update plone27_empresa_titulares set hasta=current_date
            where empresa_id=p_empresa and persona=p_persona and hasta is null returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'La persona no es titular activo de la empresa'; end if;
  delete from plone27_account_members m using plone27_empresa_cuentas ec
    where ec.empresa_id=p_empresa and m.account_id=ec.account_id and m.user_id=p_persona;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_titular_cese','empresa',p_empresa::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- Pasarela de la empresa: crea su cliente de API con permisos de una lista cerrada
create or replace function plone27_empresa_pasarela_registrar(p_bank uuid,p_empresa uuid,p_nombre text,p_key_hash text,p_scopes text[],p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank and e.estado='activa') then
    raise exception 'Empresa no encontrada o no activa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede dar de alta su pasarela';
  end if;
  if exists(select 1 from plone27_empresa_pasarelas pe where pe.empresa_id=p_empresa and pe.activa) then
    raise exception 'La empresa ya tiene una pasarela activa';
  end if;
  if p_scopes is null or array_length(p_scopes,1) is null or not(p_scopes <@ array['checkout:crear','branding:gestionar','webhooks:gestionar','origenes:gestionar','accounts:read']::text[]) then
    raise exception 'Permisos no permitidos para una pasarela de empresa';
  end if;
  insert into plone27_api_clients(bank_id,name,key_hash,scopes) values(p_bank,p_nombre,p_key_hash,p_scopes)
    returning plone27_api_clients.id into cid;
  insert into plone27_empresa_pasarelas(empresa_id,client_id) values(p_empresa,cid);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_pasarela_alta','empresa',p_empresa::text,jsonb_build_object('client',cid,'scopes',p_scopes));
  return cid; end $$;

create or replace function plone27_empresa_contrato_guardar(p_bank uuid,p_empresa uuid,p_texto text) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v int; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank) then raise exception 'Empresa no encontrada'; end if;
  select coalesce(max(c.version),0)+1 into v from plone27_empresa_contratos c where c.empresa_id=p_empresa;
  insert into plone27_empresa_contratos(empresa_id,version,texto) values(p_empresa,v,p_texto);
  return v; end $$;

create or replace function plone27_empresa_contrato_actual(p_bank uuid,p_empresa uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('version',c.version,'texto',c.texto,'creado',c.creado)
  from plone27_empresa_contratos c join plone27_empresas e on e.id=c.empresa_id
  where c.empresa_id=p_empresa and e.bank_id=p_bank order by c.version desc limit 1 $$;

create or replace function plone27_empresa_detalle(p_bank uuid,p_empresa uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb; begin
  select jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado,
    'titulares',(select coalesce(jsonb_agg(jsonb_build_object('dip',p.dip,'rol',t.rol,'desde',t.desde,'hasta',t.hasta) order by t.desde),'[]'::jsonb)
                 from plone27_empresa_titulares t join plone27_personas p on p.id=t.persona where t.empresa_id=e.id),
    'cuentas',(select coalesce(jsonb_agg(jsonb_build_object('iban',a.iban,'nombre',a.name) order by a.iban),'[]'::jsonb)
               from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id where ec.empresa_id=e.id),
    'pasarela',(select jsonb_build_object('client_id',pe.client_id,'activa',pe.activa) from plone27_empresa_pasarelas pe where pe.empresa_id=e.id),
    'contrato_version',(select max(c.version) from plone27_empresa_contratos c where c.empresa_id=e.id))
  into r from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank;
  return r; end $$;

-- NFC: identificador y/o enlace de la tarjeta (física o virtual)
create or replace function plone27_tarjeta_nfc_set(p_bank uuid,p_ref text,p_nfc text,p_enlace text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_cards cd set nfc_id=nullif(p_nfc,''), nfc_enlace=nullif(p_enlace,''), nfc_actualizado=now()
            from plone27_accounts a
            where cd.card_ref=p_ref and a.id=cd.account_id and a.bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Tarjeta no encontrada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tarjeta_nfc','card',p_ref,jsonb_build_object('nfc',nullif(p_nfc,''),'enlace',nullif(p_enlace,'')));
end $$;

create or replace function plone27_tarjeta_nfc_get(p_bank uuid,p_ref text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('nfc_id',cd.nfc_id,'nfc_enlace',cd.nfc_enlace,'actualizado',cd.nfc_actualizado)
  from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
  where cd.card_ref=p_ref and a.bank_id=p_bank $$;

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


do $$ begin raise notice 'Actualización 0036 aplicada correctamente.'; end $$;

commit;
