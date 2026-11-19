-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0027 · Cuenta institucional: presupuestos, gastos, retribuciones, tareas y nóminas
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0026.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0027 · Cuenta institucional (fases 2, 3, 4 y 6): presupuestos jerárquicos, permisos por puesto,
-- delegaciones aplicadas, gastos con doble firma, retribuciones, tareas con complementos, nóminas por periodo,
-- reasignaciones, informes, cierre de unidades y funciones para la API. Requiere 0026. Idempotente.

alter table plone27_entidades add column if not exists presupuesto_anual numeric(18,2) not null default 0 check(presupuesto_anual>=0);
alter table plone27_entidades add column if not exists doble_firma_desde numeric(18,2) check(doble_firma_desde is null or doble_firma_desde>0);

-- ---------- Permisos configurables por puesto ----------
create table if not exists plone27_puesto_permisos(
  puesto uuid not null references plone27_puestos(id),
  accion text not null check(accion in('proponer','aprobar','ejecutar','presupuestar','reasignar','retribuir','organigrama','cerrar')),
  limite numeric(18,2) check(limite is null or limite>0),
  primary key(puesto,accion));

-- ---------- Presupuesto anual por unidad y ejercicio ----------
create table if not exists plone27_presupuestos(
  unidad uuid not null references plone27_unidades(id),
  ejercicio int not null check(ejercicio between 2000 and 2100),
  anual numeric(18,2) not null default 0 check(anual>=0),
  primary key(unidad,ejercicio));

-- ---------- Gastos: propuesto → aprobado → pagado (o rechazado) ----------
create table if not exists plone27_gastos(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  unidad uuid not null references plone27_unidades(id),
  ejercicio int not null check(ejercicio between 2000 and 2100),
  importe numeric(18,2) not null check(importe>0),
  concepto text not null check(length(concepto) between 3 and 200),
  origen text not null default 'manual' check(origen in('manual','tarea','retribucion')),
  beneficiario uuid references plone27_accounts,
  propuesto_por uuid not null references plone27_personas,
  aprobado_por uuid references plone27_personas,
  pagado_por uuid references plone27_personas,
  estado text not null default 'propuesto' check(estado in('propuesto','aprobado','pagado','rechazado')),
  tx uuid,
  idem_key text unique,
  creado timestamptz not null default now(),
  resuelto timestamptz,
  check(aprobado_por is null or aprobado_por<>propuesto_por),
  check(pagado_por is null or pagado_por<>propuesto_por),
  check(pagado_por is null or aprobado_por is null or pagado_por<>aprobado_por));

-- Firmas de doble autorización (importes por encima del umbral de la entidad)
create table if not exists plone27_gasto_firmas(
  gasto uuid not null references plone27_gastos(id),
  persona uuid not null references plone27_personas,
  creada timestamptz not null default now(),
  primary key(gasto,persona));

-- ---------- Retribuciones fijas y complementos autorizados ----------
create table if not exists plone27_retribuciones(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  persona uuid not null references plone27_personas,
  concepto text not null check(length(concepto) between 3 and 120),
  importe numeric(18,2) not null check(importe>0),
  desde date not null,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  autorizada_por uuid not null references plone27_personas,
  creada timestamptz not null default now(),
  check(hasta is null or hasta>=desde));

-- ---------- Tareas que generan un complemento (las registra NEXE u otra app) ----------
create table if not exists plone27_tareas(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  persona uuid not null references plone27_personas,
  unidad uuid not null references plone27_unidades(id),
  concepto text not null check(length(concepto) between 3 and 200),
  importe numeric(18,2) not null check(importe>0),
  referencia_externa text not null unique check(length(referencia_externa) between 1 and 120),
  origen_app text not null check(length(origen_app) between 1 and 60),
  gasto uuid references plone27_gastos(id),
  estado text not null default 'registrada' check(estado in('registrada','validada','pagada','rechazada')),
  creada timestamptz not null default now());

-- ---------- Nóminas pagadas por periodo (idempotencia de la nómina) ----------
create table if not exists plone27_nominas_pagadas(
  persona uuid not null references plone27_personas,
  periodo text not null check(periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  referencia text not null,
  importe numeric(18,2) not null,
  gasto uuid references plone27_gastos(id),
  tx uuid,
  creada timestamptz not null default now(),
  primary key(persona,periodo,referencia));

-- ================= Funciones auxiliares =================
create or replace function plone27_ancestros(p_unidad uuid) returns table(id uuid)
language sql stable security definer set search_path=public as $$
  with recursive a as (
    select u.id, u.padre from plone27_unidades u where u.id=p_unidad
    union all
    select u.id, u.padre from plone27_unidades u join a on u.id=a.padre)
  select a.id from a $$;

create or replace function plone27_descendientes(p_unidad uuid) returns table(id uuid)
language sql stable security definer set search_path=public as $$
  with recursive d as (
    select u.id from plone27_unidades u where u.id=p_unidad
    union all
    select u.id from plone27_unidades u join d on u.padre=d.id)
  select d.id from d $$;

-- Lo comprometido y ejecutado de una unidad y de todas las unidades que dependen de ella
create or replace function plone27_gastado(p_unidad uuid,p_ejercicio int) returns numeric
language sql stable security definer set search_path=public as $$
  select coalesce(sum(g.importe),0) from plone27_gastos g
  where g.ejercicio=p_ejercicio and g.estado in('aprobado','pagado')
    and g.unidad in (select d.id from plone27_descendientes(p_unidad) d) $$;

create or replace function plone27_entidad_de(p_bank uuid,p_cip text) returns uuid
language sql stable security definer set search_path=public as $$
  select e.account_id from plone27_entidades e where e.cip=p_cip and e.bank_id=p_bank and e.activa $$;

create or replace function plone27_tiene_en_entidad(p_persona uuid,p_entidad uuid,p_accion text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_nombramientos n
    join plone27_puestos pu on pu.id=n.puesto and pu.activo
    join plone27_unidades u on u.id=pu.unidad and u.entidad=p_entidad
    join plone27_puesto_permisos pp on pp.puesto=pu.id and pp.accion=p_accion
    where n.persona=p_persona and n.hasta is null) $$;

create or replace function plone27_cuenta_titular(p_persona uuid,p_bank uuid) returns uuid
language sql stable security definer set search_path=public as $$
  select a.id from plone27_account_members m join plone27_accounts a on a.id=m.account_id
  where m.user_id=p_persona and a.bank_id=p_bank and a.kind='personal' and a.status='active' and m.role='holder'
  order by a.iban limit 1 $$;

create or replace function plone27_puesto_de(p_persona uuid,p_entidad uuid) returns uuid
language sql stable security definer set search_path=public as $$
  select u.id from plone27_nombramientos n
    join plone27_puestos pu on pu.id=n.puesto
    join plone27_unidades u on u.id=pu.unidad
  where n.persona=p_persona and n.hasta is null and u.entidad=p_entidad
  order by n.desde limit 1 $$;

-- ¿Puede la persona realizar la acción sobre la unidad? Por puesto (en la unidad o en sus superiores) o por delegación vigente.
create or replace function plone27_puede(p_persona uuid,p_unidad uuid,p_accion text,p_importe numeric) returns boolean
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if exists(select 1 from plone27_nombramientos n
      join plone27_puestos pu on pu.id=n.puesto and pu.activo
      join plone27_puesto_permisos pp on pp.puesto=pu.id and pp.accion=p_accion
    where n.persona=p_persona and n.hasta is null
      and pu.unidad in (select a.id from plone27_ancestros(p_unidad) a)
      and (pp.limite is null or (p_importe is not null and pp.limite>=p_importe))) then
    return true;
  end if;
  if exists(select 1 from plone27_delegaciones d
    where d.persona=p_persona and d.permiso=p_accion and d.revocada_at is null
      and d.desde<=current_date and (d.hasta is null or d.hasta>=current_date)
      and d.unidad in (select a.id from plone27_ancestros(p_unidad) a)
      and (d.limite is null or (p_importe is not null and d.limite>=p_importe))) then
    return true;
  end if;
  return false;
end $$;

-- Presupuesto suficiente en la unidad y en todas sus superiores. Cada nivel debe tener presupuesto.
create or replace function plone27_verificar_presupuesto(p_unidad uuid,p_ejercicio int,p_importe numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; asig numeric; nom text; gast numeric; begin
  for r in select x.id from plone27_ancestros(p_unidad) x loop
    select p.anual into asig from plone27_presupuestos p where p.unidad=r.id and p.ejercicio=p_ejercicio;
    select u.nombre into nom from plone27_unidades u where u.id=r.id;
    if asig is null then raise exception 'La unidad % no tiene presupuesto para %', nom, p_ejercicio; end if;
    gast:=plone27_gastado(r.id,p_ejercicio);
    if gast+p_importe>asig then raise exception 'Presupuesto insuficiente en % (disponible: %)', nom, asig-gast; end if;
  end loop;
end $$;

-- ================= Presupuestos =================
create or replace function plone27_entidad_presupuesto_fijar(p_bank uuid,p_cip text,p_actor uuid,p_importe numeric) returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para presupuestar la entidad'; end if;
  if p_importe is null or p_importe<0 then raise exception 'Importe no válido'; end if;
  update plone27_entidades set presupuesto_anual=p_importe where account_id=ent;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'entidad_presupuesto','account',ent::text,jsonb_build_object('importe',p_importe));
  return p_importe;
end $$;

-- Fija el presupuesto anual de una unidad. Los hijos no pueden sumar más que su unidad, las unidades superiores
-- no pueden sumar más que la entidad, y no se puede bajar de lo ya comprometido.
create or replace function plone27_presupuesto_fijar(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_ejercicio int,p_importe numeric) returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; pad uuid; gast numeric; hijos numeric; hermanas numeric; techo numeric; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if p_importe is null or p_importe<0 then raise exception 'Importe no válido'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_importe) then raise exception 'Sin permiso para presupuestar esta unidad'; end if;
  gast:=plone27_gastado(p_unidad,p_ejercicio);
  if p_importe<gast then raise exception 'El presupuesto no puede quedar por debajo de lo ya comprometido o gastado (%)', gast; end if;
  select coalesce(sum(p.anual),0) into hijos from plone27_presupuestos p join plone27_unidades u on u.id=p.unidad
    where u.padre=p_unidad and p.ejercicio=p_ejercicio;
  if p_importe<hijos then raise exception 'Las unidades inferiores suman % y superan este presupuesto', hijos; end if;
  select u.padre into pad from plone27_unidades u where u.id=p_unidad;
  if pad is not null then
    select coalesce(sum(p.anual),0) into hermanas from plone27_presupuestos p join plone27_unidades u on u.id=p.unidad
      where u.padre=pad and p.ejercicio=p_ejercicio and u.id<>p_unidad;
    select coalesce((select p.anual from plone27_presupuestos p where p.unidad=pad and p.ejercicio=p_ejercicio),0) into techo;
    if hermanas+p_importe>techo then raise exception 'Las unidades de este nivel superan el presupuesto de su unidad superior (%)', techo; end if;
  else
    select coalesce(sum(p.anual),0) into hermanas from plone27_presupuestos p join plone27_unidades u on u.id=p.unidad
      where u.entidad=ent and u.padre is null and p.ejercicio=p_ejercicio and u.id<>p_unidad;
    select e.presupuesto_anual into techo from plone27_entidades e where e.account_id=ent;
    if hermanas+p_importe>techo then raise exception 'Las unidades de primer nivel superan el presupuesto general de la entidad (%)', techo; end if;
  end if;
  insert into plone27_presupuestos(unidad,ejercicio,anual) values(p_unidad,p_ejercicio,p_importe)
    on conflict(unidad,ejercicio) do update set anual=excluded.anual;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'presupuesto_fijar','unidad',p_unidad::text,jsonb_build_object('ejercicio',p_ejercicio,'importe',p_importe));
  return p_importe;
end $$;

-- Mueve presupuesto entre dos unidades con la misma unidad superior. No cambia el total de la entidad.
create or replace function plone27_presupuesto_reasignar(p_bank uuid,p_cip text,p_actor uuid,p_desde uuid,p_hasta uuid,p_ejercicio int,p_importe numeric,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; pd uuid; ph uuid; asig numeric; gast numeric; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_desde=p_hasta then raise exception 'Origen y destino no pueden ser la misma unidad'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_desde and u.entidad=ent) or
     not exists(select 1 from plone27_unidades u where u.id=p_hasta and u.entidad=ent) then
    raise exception 'Unidad no encontrada en la entidad';
  end if;
  select u.padre into pd from plone27_unidades u where u.id=p_desde;
  select u.padre into ph from plone27_unidades u where u.id=p_hasta;
  if pd is distinct from ph then raise exception 'Solo se reasigna entre unidades con la misma unidad superior'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'Importe no válido'; end if;
  if length(coalesce(p_motivo,''))<5 then raise exception 'El motivo es obligatorio (mínimo 5 caracteres)'; end if;
  if not plone27_puede(p_actor,p_desde,'reasignar',p_importe) then raise exception 'Sin permiso para reasignar desde esta unidad'; end if;
  select p.anual into asig from plone27_presupuestos p where p.unidad=p_desde and p.ejercicio=p_ejercicio;
  if asig is null then raise exception 'La unidad de origen no tiene presupuesto para ese ejercicio'; end if;
  gast:=plone27_gastado(p_desde,p_ejercicio);
  if asig-gast<p_importe then raise exception 'Disponible insuficiente en la unidad de origen (%)', asig-gast; end if;
  update plone27_presupuestos set anual=anual-p_importe where unidad=p_desde and ejercicio=p_ejercicio;
  insert into plone27_presupuestos(unidad,ejercicio,anual) values(p_hasta,p_ejercicio,p_importe)
    on conflict(unidad,ejercicio) do update set anual=plone27_presupuestos.anual+excluded.anual;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'presupuesto_reasignar','unidad',p_desde::text,jsonb_build_object('destino',p_hasta,'importe',p_importe,'motivo',p_motivo));
end $$;

-- Informe de una unidad: presupuesto, comprometido, pagado, pendiente y disponible; y sus unidades inferiores
create or replace function plone27_informe_unidad(p_bank uuid,p_cip text,p_unidad uuid,p_ejercicio int) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; asig numeric; gast numeric; pag numeric; pend numeric; hijos jsonb; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  select p.anual into asig from plone27_presupuestos p where p.unidad=p_unidad and p.ejercicio=p_ejercicio;
  gast:=plone27_gastado(p_unidad,p_ejercicio);
  select coalesce(sum(g.importe),0) into pag from plone27_gastos g
    where g.ejercicio=p_ejercicio and g.estado='pagado' and g.unidad in (select d.id from plone27_descendientes(p_unidad) d);
  select coalesce(sum(g.importe),0) into pend from plone27_gastos g
    where g.ejercicio=p_ejercicio and g.estado='propuesto' and g.unidad in (select d.id from plone27_descendientes(p_unidad) d);
  select coalesce(jsonb_agg(jsonb_build_object('unidad',u.id,'nombre',u.nombre,'tipo',u.tipo,
           'anual',coalesce(p.anual,0),'gastado',plone27_gastado(u.id,p_ejercicio)) order by u.nombre),'[]'::jsonb)
    into hijos from plone27_unidades u left join plone27_presupuestos p on p.unidad=u.id and p.ejercicio=p_ejercicio
    where u.padre=p_unidad;
  return jsonb_build_object('unidad',p_unidad,'ejercicio',p_ejercicio,'anual',coalesce(asig,0),'gastado',gast,
    'pagado',pag,'pendiente_aprobacion',pend,'disponible',coalesce(asig,0)-gast,'unidades_inferiores',hijos);
end $$;

-- ================= Gastos =================
create or replace function plone27_gasto_proponer(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_ejercicio int,p_importe numeric,p_concepto text,p_iban text,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ben uuid; gid uuid; begin
  if p_key is not null then
    select g.id into gid from plone27_gastos g where g.idem_key=p_key;
    if gid is not null then return gid; end if;
  end if;
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if exists(select 1 from plone27_ancestros(p_unidad) a join plone27_unidades u on u.id=a.id where not u.activa) then
    raise exception 'La unidad o una de sus superiores está cerrada';
  end if;
  if p_importe is null or p_importe<=0 then raise exception 'Importe no válido'; end if;
  if coalesce(length(p_concepto),0)<3 then raise exception 'Concepto de al menos 3 caracteres'; end if;
  if not plone27_puede(p_actor,p_unidad,'proponer',p_importe) then raise exception 'Sin permiso para proponer gastos en esta unidad'; end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into ben from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank and a.status='active';
    if ben is null then raise exception 'Cuenta beneficiaria no válida'; end if;
  end if;
  insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,beneficiario,propuesto_por,idem_key)
    values(ent,p_unidad,p_ejercicio,p_importe,p_concepto,ben,p_actor,p_key) returning plone27_gastos.id into gid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_propuesto','gasto',gid::text,jsonb_build_object('importe',p_importe,'unidad',p_unidad));
  return gid;
end $$;

-- Aprueba un gasto. Si el importe supera el umbral de doble firma, hacen falta dos personas distintas.
create or replace function plone27_gasto_aprobar(p_bank uuid,p_gasto uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; umbral numeric; n int; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado<>'propuesto' then raise exception 'Solo se aprueban gastos propuestos'; end if;
  if p_actor=g.propuesto_por then raise exception 'Nadie puede aprobar su propio gasto'; end if;
  if not plone27_puede(p_actor,g.unidad,'aprobar',g.importe) then raise exception 'Sin permiso para aprobar este gasto'; end if;
  select e.doble_firma_desde into umbral from plone27_entidades e where e.account_id=g.entidad;
  if umbral is not null and g.importe>umbral then
    insert into plone27_gasto_firmas(gasto,persona) values(p_gasto,p_actor) on conflict do nothing;
    select count(*) into n from plone27_gasto_firmas f where f.gasto=p_gasto;
    if n<2 then return 'pendiente_segunda_firma'; end if;
  end if;
  perform 1 from plone27_presupuestos p where p.ejercicio=g.ejercicio and p.unidad in (select a.id from plone27_ancestros(g.unidad) a) for update;
  perform plone27_verificar_presupuesto(g.unidad,g.ejercicio,g.importe);
  update plone27_gastos set estado='aprobado', aprobado_por=p_actor, resuelto=now() where id=p_gasto;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_aprobado','gasto',p_gasto::text,jsonb_build_object('importe',g.importe));
  return 'aprobado';
end $$;

create or replace function plone27_gasto_rechazar(p_bank uuid,p_gasto uuid,p_actor uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado not in('propuesto','aprobado') then raise exception 'Este gasto ya no se puede rechazar'; end if;
  if p_actor=g.propuesto_por then raise exception 'Nadie puede rechazar su propio gasto'; end if;
  if not plone27_puede(p_actor,g.unidad,'aprobar',g.importe) then raise exception 'Sin permiso para rechazar este gasto'; end if;
  update plone27_gastos set estado='rechazado', resuelto=now() where id=p_gasto;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_rechazado','gasto',p_gasto::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- Ejecuta el pago de un gasto aprobado desde la cuenta de la entidad. Quien propone o aprueba no puede pagar.
create or replace function plone27_gasto_pagar(p_bank uuid,p_gasto uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; tx uuid; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado<>'aprobado' then raise exception 'Solo se pagan gastos aprobados'; end if;
  if p_actor=g.propuesto_por or p_actor=g.aprobado_por then raise exception 'Quien propone o aprueba no puede ejecutar el pago'; end if;
  if exists(select 1 from plone27_gasto_firmas f where f.gasto=p_gasto and f.persona=p_actor) then raise exception 'Quien firma no puede ejecutar el pago'; end if;
  if g.beneficiario is null then raise exception 'El gasto no tiene cuenta beneficiaria'; end if;
  if not plone27_puede(p_actor,g.unidad,'ejecutar',g.importe) then raise exception 'Sin permiso para ejecutar este pago'; end if;
  tx:=plone27_transfer('gasto:'||g.id::text,g.entidad,g.beneficiario,g.importe,g.concepto,p_actor);
  update plone27_gastos set estado='pagado', pagado_por=p_actor, tx=tx, resuelto=now() where id=p_gasto;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_pagado','gasto',p_gasto::text,jsonb_build_object('importe',g.importe,'tx',tx));
  return tx;
end $$;

-- ================= Retribuciones y tareas =================
create or replace function plone27_retribucion_fijar(p_bank uuid,p_cip text,p_actor uuid,p_persona uuid,p_concepto text,p_importe numeric,p_desde date,p_hasta date,p_motivo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; unidad uuid; rid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  unidad:=plone27_puesto_de(p_persona,ent);
  if unidad is null then raise exception 'La persona no tiene puesto en la entidad'; end if;
  if p_actor=p_persona then raise exception 'Nadie puede autorizar su propia retribución'; end if;
  if not plone27_puede(p_actor,unidad,'retribuir',p_importe) then raise exception 'Sin permiso para retribuir a esta persona'; end if;
  insert into plone27_retribuciones(entidad,persona,concepto,importe,desde,hasta,motivo,autorizada_por)
    values(ent,p_persona,p_concepto,p_importe,p_desde,p_hasta,p_motivo,p_actor) returning plone27_retribuciones.id into rid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'retribucion_fijada','retribucion',rid::text,jsonb_build_object('importe',p_importe,'concepto',p_concepto));
  return rid;
end $$;

-- Una tarea registrada por una app externa genera un gasto propuesto a nombre de la persona que la realizó.
create or replace function plone27_tarea_registrar(p_bank uuid,p_cip text,p_persona uuid,p_unidad uuid,p_concepto text,p_importe numeric,p_referencia text,p_origen text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ben uuid; gid uuid; tid uuid; begin
  select t.id into tid from plone27_tareas t where t.referencia_externa=p_referencia;
  if tid is not null then return tid; end if;
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  if plone27_puesto_de(p_persona,ent) is null then raise exception 'La persona no tiene puesto en la entidad'; end if;
  ben:=plone27_cuenta_titular(p_persona,p_bank);
  if ben is null then raise exception 'La persona no tiene cuenta en la entidad'; end if;
  insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,origen,beneficiario,propuesto_por)
    values(ent,p_unidad,extract(year from current_date)::int,p_importe,p_concepto,'tarea',ben,p_persona)
    returning plone27_gastos.id into gid;
  insert into plone27_tareas(entidad,persona,unidad,concepto,importe,referencia_externa,origen_app,gasto)
    values(ent,p_persona,p_unidad,p_concepto,p_importe,p_referencia,p_origen,gid) returning plone27_tareas.id into tid;
  return tid;
end $$;

create or replace function plone27_tarea_validar(p_bank uuid,p_tarea uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t plone27_tareas; r text; begin
  select * into t from plone27_tareas where id=p_tarea for update;
  if t.id is null or not exists(select 1 from plone27_entidades e where e.account_id=t.entidad and e.bank_id=p_bank) then raise exception 'Tarea no encontrada'; end if;
  if t.estado<>'registrada' then raise exception 'La tarea no está pendiente de validación'; end if;
  r:=plone27_gasto_aprobar(p_bank,t.gasto,p_actor);
  if r='aprobado' then update plone27_tareas set estado='validada' where id=p_tarea; end if;
  return r;
end $$;

create or replace function plone27_tarea_pagar(p_bank uuid,p_tarea uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t plone27_tareas; tx uuid; begin
  select * into t from plone27_tareas where id=p_tarea for update;
  if t.id is null or not exists(select 1 from plone27_entidades e where e.account_id=t.entidad and e.bank_id=p_bank) then raise exception 'Tarea no encontrada'; end if;
  if t.estado<>'validada' then raise exception 'Solo se pagan tareas validadas'; end if;
  tx:=plone27_gasto_pagar(p_bank,t.gasto,p_actor);
  update plone27_tareas set estado='pagada' where id=p_tarea;
  return tx;
end $$;

create or replace function plone27_tarea_rechazar(p_bank uuid,p_tarea uuid,p_actor uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t plone27_tareas; begin
  select * into t from plone27_tareas where id=p_tarea for update;
  if t.id is null or not exists(select 1 from plone27_entidades e where e.account_id=t.entidad and e.bank_id=p_bank) then raise exception 'Tarea no encontrada'; end if;
  if t.estado not in('registrada','validada') then raise exception 'Esta tarea ya no se puede rechazar'; end if;
  perform plone27_gasto_rechazar(p_bank,t.gasto,p_actor,p_motivo);
  update plone27_tareas set estado='rechazada' where id=p_tarea;
end $$;

-- ================= Nómina por periodo =================
-- Paga todas las retribuciones fijas vigentes en el periodo (AAAA-MM). Una nómina ya pagada no se repite.
-- Si un solo pago no tiene presupuesto, no se paga ninguno (la transacción se deshace).
create or replace function plone27_nomina_periodo(p_bank uuid,p_cip text,p_actor uuid,p_periodo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ini date; fin date; ejer int; r plone27_retribuciones; unidad uuid; ben uuid; ref text; gid uuid; tx uuid; n int:=0; total numeric:=0; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'ejecutar') then raise exception 'Sin permiso para ejecutar nóminas'; end if;
  ini:=to_date(p_periodo||'-01','YYYY-MM-DD');
  fin:=(ini+interval '1 month'-interval '1 day')::date;
  ejer:=extract(year from ini)::int;
  for r in select x.* from plone27_retribuciones x
           where x.entidad=ent and x.desde<=fin and (x.hasta is null or x.hasta>=ini) order by x.id loop
    ref:='retribucion:'||r.id::text;
    if exists(select 1 from plone27_nominas_pagadas np where np.persona=r.persona and np.periodo=p_periodo and np.referencia=ref) then
      continue;
    end if;
    unidad:=plone27_puesto_de(r.persona,ent);
    if unidad is null then raise exception 'Una persona con retribución no tiene puesto en la entidad'; end if;
    ben:=plone27_cuenta_titular(r.persona,p_bank);
    if ben is null then raise exception 'Una persona con retribución no tiene cuenta en la entidad'; end if;
    if r.autorizada_por=p_actor then raise exception 'Quien autoriza una retribución no puede ejecutar la nómina'; end if;
    perform plone27_verificar_presupuesto(unidad,ejer,r.importe);
    tx:=plone27_transfer('nomina:'||p_periodo||':'||r.id::text,ent,ben,r.importe,'Nómina '||p_periodo,p_actor);
    insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,origen,beneficiario,propuesto_por,pagado_por,estado,tx,resuelto)
      values(ent,unidad,ejer,r.importe,r.concepto||' '||p_periodo,'retribucion',ben,r.autorizada_por,p_actor,'pagado',tx,now())
      returning plone27_gastos.id into gid;
    insert into plone27_nominas_pagadas(persona,periodo,referencia,importe,gasto,tx)
      values(r.persona,p_periodo,ref,r.importe,gid,tx);
    n:=n+1; total:=total+r.importe;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'nomina_periodo','account',ent::text,jsonb_build_object('periodo',p_periodo,'pagos',n,'total',total));
  return jsonb_build_object('periodo',p_periodo,'pagos',n,'total',total);
end $$;

-- ================= Organigrama para la API (con comprobación de permisos y entidad) =================
create or replace function plone27_arbol(p_bank uuid,p_cip text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; resultado jsonb; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then return null; end if;
  select jsonb_build_object('entidad',e.nombre,'cip',e.cip,
    'unidades',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'padre',u.padre,'tipo',u.tipo,'nombre',u.nombre,'codigo',u.codigo,'activa',u.activa) order by u.nombre),'[]'::jsonb)
                from plone27_unidades u where u.entidad=ent),
    'puestos',(select coalesce(jsonb_agg(jsonb_build_object('id',pu.id,'unidad',pu.unidad,'nombre',pu.nombre,'titulares_max',pu.titulares_max,'activo',pu.activo) order by pu.nombre),'[]'::jsonb)
                from plone27_puestos pu join plone27_unidades u on u.id=pu.unidad where u.entidad=ent),
    'nombramientos',(select coalesce(jsonb_agg(jsonb_build_object('dip',pe.dip,'puesto',n.puesto,'desde',n.desde) order by n.desde),'[]'::jsonb)
                from plone27_nombramientos n join plone27_puestos pu on pu.id=n.puesto
                join plone27_unidades u on u.id=pu.unidad join plone27_personas pe on pe.id=n.persona
                where u.entidad=ent and n.hasta is null))
  into resultado from plone27_entidades e where e.account_id=ent;
  return resultado;
end $$;

-- Expediente de una persona en la entidad: puestos, retribuciones vigentes, tareas y nóminas pagadas
create or replace function plone27_expediente(p_bank uuid,p_cip text,p_persona uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then return null; end if;
  return jsonb_build_object(
    'puestos',(select coalesce(jsonb_agg(jsonb_build_object('puesto',pu.nombre,'unidad',u.nombre,'desde',n.desde) order by n.desde),'[]'::jsonb)
               from plone27_nombramientos n join plone27_puestos pu on pu.id=n.puesto join plone27_unidades u on u.id=pu.unidad
               where n.persona=p_persona and n.hasta is null and u.entidad=ent),
    'retribuciones',(select coalesce(jsonb_agg(jsonb_build_object('concepto',r.concepto,'importe',r.importe,'desde',r.desde,'hasta',r.hasta) order by r.desde),'[]'::jsonb)
               from plone27_retribuciones r where r.persona=p_persona and r.entidad=ent and (r.hasta is null or r.hasta>=current_date)),
    'tareas',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
               select t.id,t.concepto,t.importe,t.estado,t.referencia_externa as referencia from plone27_tareas t
               where t.persona=p_persona and t.entidad=ent order by t.creada desc limit 50) x),
    'nominas',(select coalesce(jsonb_agg(to_jsonb(y)),'[]'::jsonb) from (
               select np.periodo,np.importe from plone27_nominas_pagadas np join plone27_gastos g on g.id=np.gasto
               where np.persona=p_persona and g.entidad=ent order by np.periodo desc limit 24) y));
end $$;

-- ================= Organigrama con permisos (API de bancos) =================
create or replace function plone27_org_unidad_nueva(p_bank uuid,p_cip text,p_actor uuid,p_tipo text,p_padre uuid,p_nombre text,p_codigo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if p_padre is not null and not exists(select 1 from plone27_unidades u where u.id=p_padre and u.entidad=ent and u.activa) then
    raise exception 'Unidad superior no válida o cerrada';
  end if;
  return plone27_unidad_alta(ent,p_tipo,p_padre,p_nombre,p_codigo,p_actor);
end $$;

create or replace function plone27_org_puesto_nuevo(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_nombre text,p_titulares int) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  return plone27_puesto_alta(p_unidad,p_nombre,p_titulares,p_actor);
end $$;

create or replace function plone27_org_nombrar(p_bank uuid,p_cip text,p_actor uuid,p_puesto uuid,p_persona uuid,p_motivo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_puestos pu join plone27_unidades u on u.id=pu.unidad where pu.id=p_puesto and u.entidad=ent) then
    raise exception 'Puesto no encontrado en la entidad';
  end if;
  return plone27_nombrar(p_puesto,p_persona,p_motivo,p_actor);
end $$;

create or replace function plone27_org_cesar(p_bank uuid,p_cip text,p_actor uuid,p_nombramiento uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_nombramientos n join plone27_puestos pu on pu.id=n.puesto
                join plone27_unidades u on u.id=pu.unidad where n.id=p_nombramiento and u.entidad=ent) then
    raise exception 'Nombramiento no encontrado en la entidad';
  end if;
  perform plone27_cesar(p_nombramiento,p_motivo,p_actor);
end $$;

create or replace function plone27_org_permiso(p_bank uuid,p_cip text,p_actor uuid,p_puesto uuid,p_accion text,p_limite numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_puestos pu join plone27_unidades u on u.id=pu.unidad where pu.id=p_puesto and u.entidad=ent) then
    raise exception 'Puesto no encontrado en la entidad';
  end if;
  insert into plone27_puesto_permisos(puesto,accion,limite) values(p_puesto,p_accion,p_limite)
    on conflict(puesto,accion) do update set limite=excluded.limite;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'puesto_permiso','puesto',p_puesto::text,jsonb_build_object('accion',p_accion,'limite',p_limite));
end $$;

-- Permisos de puesto para el personal del banco (arranque del sistema). No se expone a las APIs.
create or replace function plone27_puesto_permiso_fijar_staff(p_puesto uuid,p_accion text,p_limite numeric,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  insert into plone27_puesto_permisos(puesto,accion,limite) values(p_puesto,p_accion,p_limite)
    on conflict(puesto,accion) do update set limite=excluded.limite;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'puesto_permiso_staff','puesto',p_puesto::text,jsonb_build_object('accion',p_accion,'limite',p_limite));
end $$;

create or replace function plone27_org_cerrar_unidad(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'cerrar',null) then raise exception 'Sin permiso para cerrar esta unidad'; end if;
  if exists(select 1 from plone27_gastos g where g.estado in('propuesto','aprobado')
            and g.unidad in (select d.id from plone27_descendientes(p_unidad) d)) then
    raise exception 'Hay gastos pendientes o comprometidos en esta unidad';
  end if;
  update plone27_unidades set activa=false where id=p_unidad;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'unidad_cerrada','unidad',p_unidad::text,jsonb_build_object('motivo',p_motivo));
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


do $$ begin raise notice 'Actualización 0027 aplicada correctamente.'; end $$;

commit;
