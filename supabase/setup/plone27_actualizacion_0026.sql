-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0026 · Cuenta institucional (fase 1)
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0025.
-- AÑADE: CIP, organigrama, puestos, multicargos, historial de nombramientos y delegaciones.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0026 · Cuenta institucional (fase 1): CIP, organigrama, puestos, multicargos,
-- historial de nombramientos y delegaciones. Requiere 0025. Idempotente.
-- Supuestos: el CIP lo genera la plataforma (CIP-00000001…); las personas se identifican por DIP.

create sequence if not exists plone27_cip_seq;

create table if not exists plone27_entidades(
  account_id uuid primary key references plone27_accounts,
  bank_id uuid not null references plone27_banks,
  cip text not null unique default ('CIP-'||lpad(nextval('plone27_cip_seq')::text,8,'0'))
    check(cip ~ '^CIP-[0-9]{8}$'),
  nombre text not null check(length(nombre) between 2 and 120),
  activa boolean not null default true,
  creada timestamptz not null default now());

create table if not exists plone27_unidades(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  padre uuid references plone27_unidades(id),
  tipo text not null check(tipo in('junta','administracion','departamento','subdepartamento','proyecto','institucion','unidad_control')),
  nombre text not null check(length(nombre) between 2 and 120),
  codigo text check(codigo is null or codigo ~ '^[A-Z0-9-]{2,20}$'),
  activa boolean not null default true,
  creada timestamptz not null default now(),
  unique(entidad,codigo));

-- Jerarquía permitida: Junta / Administración → departamentos; departamento → subdepartamentos y proyectos;
-- Junta / Administración → instituciones; departamento, subdepartamento o proyecto → unidades de control.
create or replace function plone27_unidad_jerarquia() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare pt text; pe uuid; begin
  if new.padre is null then
    if new.tipo in('junta','administracion','institucion') then return new; end if;
    raise exception 'Una unidad de tipo % necesita una unidad padre', new.tipo;
  end if;
  if new.padre=new.id then raise exception 'Una unidad no puede depender de sí misma'; end if;
  select u.tipo,u.entidad into pt,pe from plone27_unidades u where u.id=new.padre;
  if pt is null then raise exception 'La unidad padre no existe'; end if;
  if pe<>new.entidad then raise exception 'La unidad padre pertenece a otra entidad'; end if;
  if new.tipo in('junta','administracion') then raise exception 'Junta y Administración no dependen de otra unidad'; end if;
  if new.tipo='departamento' and pt not in('junta','administracion') then raise exception 'Un departamento depende de Junta o Administración'; end if;
  if new.tipo='subdepartamento' and pt<>'departamento' then raise exception 'Un subdepartamento depende de un departamento'; end if;
  if new.tipo='proyecto' and pt not in('departamento','subdepartamento') then raise exception 'Un proyecto depende de un departamento o subdepartamento'; end if;
  if new.tipo='institucion' and pt not in('junta','administracion') then raise exception 'Una institución depende de Junta o Administración'; end if;
  if new.tipo='unidad_control' and pt not in('departamento','subdepartamento','proyecto') then raise exception 'Una unidad de control depende de un departamento, subdepartamento o proyecto'; end if;
  return new; end $$;

drop trigger if exists t_unidad_jerarquia on plone27_unidades;
drop trigger if exists t_unidad_jerarquia on plone27_unidades;
create trigger t_unidad_jerarquia before insert or update on plone27_unidades
  for each row execute function plone27_unidad_jerarquia();

create table if not exists plone27_puestos(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  nombre text not null check(length(nombre) between 2 and 120),
  titulares_max int not null default 1 check(titulares_max between 1 and 50),
  activo boolean not null default true,
  creado timestamptz not null default now());

-- Historial: cada nombramiento queda registrado; el cese cierra el periodo (hasta), no lo borra.
create table if not exists plone27_nombramientos(
  id uuid primary key default gen_random_uuid(),
  puesto uuid not null references plone27_puestos(id),
  persona uuid not null references plone27_personas,
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  nombrado_por uuid,
  cesado_por uuid,
  check(hasta is null or hasta>=desde));
create unique index if not exists plone27_nombramiento_activo_ux on plone27_nombramientos(puesto,persona) where hasta is null;

-- Delegaciones: registro de quién puede actuar en un área. Aún no condicionan las aprobaciones (fase 3).
create table if not exists plone27_delegaciones(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  persona uuid not null references plone27_personas,
  permiso text not null check(permiso in('consultar','proponer','aprobar','ejecutar')),
  limite numeric(18,2) check(limite is null or limite>0),
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  otorgada_por uuid,
  revocada_at timestamptz,
  check(hasta is null or hasta>=desde));

create or replace function plone27_entidad_alta(p_bank uuid,p_account uuid,p_nombre text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c text; begin
  if not exists(select 1 from plone27_accounts a where a.id=p_account and a.bank_id=p_bank) then
    raise exception 'Cuenta no encontrada en la entidad';
  end if;
  insert into plone27_entidades(account_id,bank_id,nombre) values(p_account,p_bank,p_nombre) returning plone27_entidades.cip into c;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'entidad_alta','account',p_account::text,jsonb_build_object('cip',c,'nombre',p_nombre));
  return c; end $$;

create or replace function plone27_unidad_alta(p_entidad uuid,p_tipo text,p_padre uuid,p_nombre text,p_codigo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare uid uuid; begin
  insert into plone27_unidades(entidad,tipo,padre,nombre,codigo) values(p_entidad,p_tipo,p_padre,p_nombre,p_codigo)
    returning plone27_unidades.id into uid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'unidad_alta','unidad',uid::text,jsonb_build_object('tipo',p_tipo,'nombre',p_nombre));
  return uid; end $$;

create or replace function plone27_puesto_alta(p_unidad uuid,p_nombre text,p_titulares int,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; begin
  insert into plone27_puestos(unidad,nombre,titulares_max) values(p_unidad,p_nombre,coalesce(p_titulares,1))
    returning plone27_puestos.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'puesto_alta','puesto',pid::text,jsonb_build_object('nombre',p_nombre));
  return pid; end $$;

-- Nombrar a una persona en un puesto. Una persona puede tener varios puestos (multicargo).
create or replace function plone27_nombrar(p_puesto uuid,p_persona uuid,p_motivo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare maximo int; ocupados int; nid uuid; begin
  select p.titulares_max into maximo from plone27_puestos p where p.id=p_puesto and p.activo;
  if maximo is null then raise exception 'Puesto no encontrado o inactivo'; end if;
  select count(*) into ocupados from plone27_nombramientos n where n.puesto=p_puesto and n.hasta is null;
  if ocupados>=maximo then raise exception 'El puesto está completo (% de %)', ocupados, maximo; end if;
  insert into plone27_nombramientos(puesto,persona,motivo,nombrado_por) values(p_puesto,p_persona,p_motivo,p_actor)
    returning plone27_nombramientos.id into nid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'nombramiento_alta','puesto',p_puesto::text,jsonb_build_object('persona',p_persona,'nombramiento',nid));
  return nid; end $$;

-- Cesar: cierra el periodo activo del nombramiento
create or replace function plone27_cesar(p_nombramiento uuid,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_nombramientos set hasta=current_date,cesado_por=p_actor
            where id=p_nombramiento and hasta is null returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Nombramiento no encontrado o ya cesado'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'nombramiento_cese','nombramiento',p_nombramiento::text,jsonb_build_object('motivo',p_motivo));
end $$;

create or replace function plone27_delegar(p_unidad uuid,p_persona uuid,p_permiso text,p_limite numeric,p_hasta date,p_motivo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare did uuid; begin
  insert into plone27_delegaciones(unidad,persona,permiso,limite,hasta,motivo,otorgada_por)
    values(p_unidad,p_persona,p_permiso,p_limite,p_hasta,p_motivo,p_actor) returning plone27_delegaciones.id into did;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'delegacion_alta','unidad',p_unidad::text,jsonb_build_object('persona',p_persona,'permiso',p_permiso));
  return did; end $$;

create or replace function plone27_revocar_delegacion(p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_delegaciones set revocada_at=now()
            where id=p_id and revocada_at is null returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Delegación no encontrada o ya revocada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'delegacion_revocada','delegacion',p_id::text,'{}'::jsonb);
end $$;

-- Plantilla vigente de una entidad: personas con su puesto y unidad
create or replace function plone27_plantilla(p_entidad uuid)
returns table(persona uuid,unidad text,puesto text,desde date)
language sql stable security definer set search_path=public as $$
  select n.persona, u.nombre, p.nombre, n.desde
  from plone27_nombramientos n
    join plone27_puestos p on p.id=n.puesto
    join plone27_unidades u on u.id=p.unidad
  where u.entidad=p_entidad and n.hasta is null
  order by u.nombre, p.nombre $$;

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


do $$ begin raise notice 'Actualización 0026 aplicada correctamente.'; end $$;

commit;
