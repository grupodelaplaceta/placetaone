-- Placeta One · 0028 · Cuenta institucional (completar): fondos restringidos, presupuestos mensuales y plurianuales,
-- pagos recurrentes, convocatorias internas, solicitudes de unidades (activables por la entidad) y eventos de webhook
-- para gastos, tareas y nóminas. Requiere 0027. Idempotente.

alter table plone27_entidades add column if not exists solicitudes_activas boolean not null default false;
alter table plone27_gastos add column if not exists fecha date not null default current_date;

-- ---------- Fondos restringidos a una finalidad ----------
create table if not exists plone27_fondos(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  nombre text not null check(length(nombre) between 2 and 120),
  finalidad text not null check(length(finalidad) between 5 and 300),
  importe numeric(18,2) not null check(importe>0),
  activo boolean not null default true,
  creado timestamptz not null default now(),
  unique(unidad,nombre));
alter table plone27_gastos add column if not exists fondo uuid references plone27_fondos(id);

-- ---------- Presupuesto mensual (reparto del anual) y plan plurianual (sobre de varios años) ----------
create table if not exists plone27_presupuesto_meses(
  unidad uuid not null references plone27_unidades(id),
  ejercicio int not null check(ejercicio between 2000 and 2100),
  mes int not null check(mes between 1 and 12),
  importe numeric(18,2) not null check(importe>=0),
  primary key(unidad,ejercicio,mes));

create table if not exists plone27_planes_plurianuales(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  nombre text not null check(length(nombre) between 2 and 120),
  ejercicio_inicio int not null check(ejercicio_inicio between 2000 and 2100),
  ejercicio_fin int not null check(ejercicio_fin between 2000 and 2100),
  total numeric(18,2) not null check(total>0),
  creado timestamptz not null default now(),
  check(ejercicio_fin>=ejercicio_inicio and ejercicio_fin-ejercicio_inicio<=9));

-- ---------- Pagos recurrentes autorizados ----------
create table if not exists plone27_recurrentes(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  unidad uuid not null references plone27_unidades(id),
  concepto text not null check(length(concepto) between 3 and 200),
  importe numeric(18,2) not null check(importe>0),
  beneficiario uuid references plone27_accounts,
  periodicidad_meses int not null check(periodicidad_meses between 1 and 12),
  desde date not null,
  hasta date,
  autorizada_por uuid not null references plone27_personas,
  activo boolean not null default true,
  creada timestamptz not null default now(),
  check(hasta is null or hasta>=desde));

create table if not exists plone27_recurrentes_generados(
  recurrente uuid not null references plone27_recurrentes(id),
  periodo text not null check(periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  gasto uuid references plone27_gastos(id),
  primary key(recurrente,periodo));

-- ---------- Convocatorias internas y solicitudes de unidades ----------
create table if not exists plone27_convocatorias(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  nombre text not null check(length(nombre) between 3 and 120),
  importe numeric(18,2) not null check(importe>0),
  desde date not null,
  hasta date not null,
  estado text not null default 'abierta' check(estado in('abierta','cerrada')),
  creada timestamptz not null default now(),
  check(hasta>=desde));

create table if not exists plone27_solicitudes_unidad(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  unidad uuid not null references plone27_unidades(id),
  tipo text not null check(tipo in('ampliacion','prorroga','reserva_extra','financiacion','otra')),
  importe numeric(18,2) check(importe is null or importe>0),
  referencia uuid,
  convocatoria uuid references plone27_convocatorias(id),
  nueva_fecha date,
  justificacion text not null check(length(justificacion) between 20 and 1000),
  estado text not null default 'pendiente' check(estado in('pendiente','concedida','denegada')),
  solicitada_por uuid not null references plone27_personas,
  resuelta_por uuid references plone27_personas,
  resolucion text check(resolucion is null or length(resolucion)<=500),
  creada timestamptz not null default now(),
  resuelta timestamptz,
  check(resuelta_por is null or resuelta_por<>solicitada_por));

-- ================= Reglas automáticas (disparadores) =================

-- Reparto mensual: no puede superar el anual
create or replace function plone27_trg_mes_valido() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare anual numeric; suma numeric; begin
  select p.anual into anual from plone27_presupuestos p where p.unidad=new.unidad and p.ejercicio=new.ejercicio;
  if anual is null then raise exception 'Primero hay que fijar el presupuesto anual de la unidad'; end if;
  select coalesce(sum(m.importe),0) into suma from plone27_presupuesto_meses m
    where m.unidad=new.unidad and m.ejercicio=new.ejercicio and m.mes<>new.mes;
  if suma+new.importe>anual then raise exception 'El reparto mensual supera el presupuesto anual (%)', anual; end if;
  return new;
end $$;
drop trigger if exists trg_mes_valido on plone27_presupuesto_meses;
create trigger trg_mes_valido before insert or update on plone27_presupuesto_meses
  for each row execute function plone27_trg_mes_valido();

-- Cambiar el anual no puede dejar por debajo el reparto mensual ni el sobre de un plan plurianual
create or replace function plone27_trg_presupuesto_coherente() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare suma_meses numeric; suma_plan numeric; pl record; begin
  select coalesce(sum(m.importe),0) into suma_meses from plone27_presupuesto_meses m
    where m.unidad=new.unidad and m.ejercicio=new.ejercicio;
  if suma_meses>new.anual then raise exception 'El reparto mensual (%) supera el nuevo presupuesto anual', suma_meses; end if;
  for pl in select x.* from plone27_planes_plurianuales x
            where x.unidad=new.unidad and new.ejercicio between x.ejercicio_inicio and x.ejercicio_fin loop
    select coalesce(sum(p.anual),0) into suma_plan from plone27_presupuestos p
      where p.unidad=new.unidad and p.ejercicio between pl.ejercicio_inicio and pl.ejercicio_fin;
    if suma_plan>pl.total then raise exception 'El plan plurianual "%" supera su total (%)', pl.nombre, pl.total; end if;
  end loop;
  return new;
end $$;
drop trigger if exists trg_presupuesto_coherente on plone27_presupuestos;
create trigger trg_presupuesto_coherente after insert or update on plone27_presupuestos
  for each row execute function plone27_trg_presupuesto_coherente();

-- Al aprobar un gasto: saldo del fondo y saldo del mes (si hay presupuesto mensual)
create or replace function plone27_trg_gasto_saldos() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare fmax numeric; usado numeric; mes_b numeric; usado_mes numeric; mes int; begin
  if new.estado<>'aprobado' or old.estado='aprobado' then return new; end if;
  if new.fondo is not null then
    select f.importe into fmax from plone27_fondos f where f.id=new.fondo;
    select coalesce(sum(g.importe),0) into usado from plone27_gastos g
      where g.fondo=new.fondo and g.estado in('aprobado','pagado') and g.id<>new.id;
    if usado+new.importe>fmax then raise exception 'El fondo no tiene saldo suficiente (disponible: %)', fmax-usado; end if;
  end if;
  mes:=extract(month from new.fecha)::int;
  select m.importe into mes_b from plone27_presupuesto_meses m
    where m.unidad=new.unidad and m.ejercicio=new.ejercicio and m.mes=mes;
  if mes_b is not null then
    select coalesce(sum(g.importe),0) into usado_mes from plone27_gastos g
      where g.unidad=new.unidad and g.ejercicio=new.ejercicio and extract(month from g.fecha)::int=mes
        and g.estado in('aprobado','pagado') and g.id<>new.id;
    if usado_mes+new.importe>mes_b then raise exception 'Presupuesto del mes insuficiente (disponible: %)', mes_b-usado_mes; end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_gasto_saldos on plone27_gastos;
create trigger trg_gasto_saldos before update of estado on plone27_gastos
  for each row execute function plone27_trg_gasto_saldos();

-- Eventos de webhook: gastos, tareas y nóminas
create or replace function plone27_trg_evento_gasto() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare bk uuid; begin
  if tg_op='UPDATE' and new.estado=old.estado then return new; end if;
  select e.bank_id into bk from plone27_entidades e where e.account_id=new.entidad;
  insert into plone27_outbox(event,bank_ids,payload) values('gasto.'||new.estado,array[bk],
    jsonb_build_object('gasto',new.id,'unidad',new.unidad,'ejercicio',new.ejercicio,'importe',new.importe,
      'concepto',new.concepto,'origen',new.origen,'estado',new.estado));
  return new;
end $$;
drop trigger if exists trg_evento_gasto on plone27_gastos;
create trigger trg_evento_gasto after insert or update of estado on plone27_gastos
  for each row execute function plone27_trg_evento_gasto();

create or replace function plone27_trg_evento_tarea() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare bk uuid; dni text; begin
  if tg_op='UPDATE' and new.estado=old.estado then return new; end if;
  select e.bank_id into bk from plone27_entidades e where e.account_id=new.entidad;
  select p.dip into dni from plone27_personas p where p.id=new.persona;
  insert into plone27_outbox(event,bank_ids,payload) values('tarea.'||new.estado,array[bk],
    jsonb_build_object('tarea',new.id,'referencia',new.referencia_externa,'dip',dni,'concepto',new.concepto,
      'importe',new.importe,'estado',new.estado));
  return new;
end $$;
drop trigger if exists trg_evento_tarea on plone27_tareas;
create trigger trg_evento_tarea after insert or update of estado on plone27_tareas
  for each row execute function plone27_trg_evento_tarea();

create or replace function plone27_trg_evento_nomina() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare bk uuid; ent uuid; dni text; begin
  select g.entidad into ent from plone27_gastos g where g.id=new.gasto;
  select e.bank_id into bk from plone27_entidades e where e.account_id=ent;
  select p.dip into dni from plone27_personas p where p.id=new.persona;
  insert into plone27_outbox(event,bank_ids,payload) values('nomina.pagada',array[bk],
    jsonb_build_object('dip',dni,'periodo',new.periodo,'importe',new.importe,'referencia',new.referencia,'gasto',new.gasto));
  return new;
end $$;
drop trigger if exists trg_evento_nomina on plone27_nominas_pagadas;
create trigger trg_evento_nomina after insert on plone27_nominas_pagadas
  for each row execute function plone27_trg_evento_nomina();

-- ================= Funciones de gestión =================

create or replace function plone27_entidad_config(p_bank uuid,p_cip text,p_actor uuid,p_solicitudes boolean,p_doble_firma numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para configurar la entidad'; end if;
  update plone27_entidades set solicitudes_activas=coalesce(p_solicitudes,false), doble_firma_desde=p_doble_firma where account_id=ent;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'entidad_config','account',ent::text,jsonb_build_object('solicitudes',p_solicitudes,'doble_firma',p_doble_firma));
end $$;

create or replace function plone27_presupuesto_mes_fijar(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_ejercicio int,p_mes int,p_importe numeric) returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_importe) then raise exception 'Sin permiso para presupuestar esta unidad'; end if;
  insert into plone27_presupuesto_meses(unidad,ejercicio,mes,importe) values(p_unidad,p_ejercicio,p_mes,p_importe)
    on conflict(unidad,ejercicio,mes) do update set importe=excluded.importe;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'presupuesto_mes','unidad',p_unidad::text,jsonb_build_object('ejercicio',p_ejercicio,'mes',p_mes,'importe',p_importe));
  return p_importe;
end $$;

create or replace function plone27_plan_plurianual_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_nombre text,p_inicio int,p_fin int,p_total numeric) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ya numeric; pid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_total) then raise exception 'Sin permiso para presupuestar esta unidad'; end if;
  select coalesce(sum(p.anual),0) into ya from plone27_presupuestos p
    where p.unidad=p_unidad and p.ejercicio between p_inicio and p_fin;
  if ya>p_total then raise exception 'Los presupuestos anuales ya suman % en esos años', ya; end if;
  insert into plone27_planes_plurianuales(unidad,nombre,ejercicio_inicio,ejercicio_fin,total)
    values(p_unidad,p_nombre,p_inicio,p_fin,p_total) returning plone27_planes_plurianuales.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'plan_plurianual','unidad',p_unidad::text,jsonb_build_object('plan',pid,'total',p_total));
  return pid;
end $$;

create or replace function plone27_fondo_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_nombre text,p_finalidad text,p_importe numeric) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; fid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_importe) then raise exception 'Sin permiso para crear fondos en esta unidad'; end if;
  insert into plone27_fondos(unidad,nombre,finalidad,importe) values(p_unidad,p_nombre,p_finalidad,p_importe)
    returning plone27_fondos.id into fid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'fondo_crear','unidad',p_unidad::text,jsonb_build_object('fondo',fid,'importe',p_importe));
  return fid;
end $$;

-- Asigna un fondo a un gasto propuesto. Solo quien propone el gasto, y el fondo debe ser de su unidad o de una superior.
create or replace function plone27_gasto_asignar_fondo(p_bank uuid,p_gasto uuid,p_actor uuid,p_fondo uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado<>'propuesto' then raise exception 'Solo se puede asignar fondo a un gasto propuesto'; end if;
  if p_actor<>g.propuesto_por then raise exception 'Solo quien propone el gasto puede asignarle un fondo'; end if;
  if not exists(select 1 from plone27_fondos f where f.id=p_fondo and f.activo and f.unidad in (select a.id from plone27_ancestros(g.unidad) a)) then
    raise exception 'Fondo no disponible para esta unidad';
  end if;
  update plone27_gastos set fondo=p_fondo where id=p_gasto;
end $$;

create or replace function plone27_recurrente_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_concepto text,p_importe numeric,p_iban text,p_meses int,p_desde date,p_hasta date) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ben uuid; rid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  if not plone27_puede(p_actor,p_unidad,'aprobar',p_importe) then raise exception 'Sin permiso para autorizar pagos recurrentes en esta unidad'; end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into ben from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank and a.status='active';
    if ben is null then raise exception 'Cuenta beneficiaria no válida'; end if;
  end if;
  insert into plone27_recurrentes(entidad,unidad,concepto,importe,beneficiario,periodicidad_meses,desde,hasta,autorizada_por)
    values(ent,p_unidad,p_concepto,p_importe,ben,p_meses,p_desde,p_hasta,p_actor) returning plone27_recurrentes.id into rid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'recurrente_crear','unidad',p_unidad::text,jsonb_build_object('recurrente',rid,'importe',p_importe));
  return rid;
end $$;

-- Genera las propuestas de gasto de los pagos recurrentes que tocan en el periodo (AAAA-MM).
-- Cada propuesta sigue su flujo normal: aprobación por otra persona, presupuesto y pago.
create or replace function plone27_recurrentes_generar(p_bank uuid,p_cip text,p_actor uuid,p_periodo text) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ini date; fin date; meses_desde int; meses_periodo int; r plone27_recurrentes; gid uuid; n int:=0; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'aprobar') then raise exception 'Sin permiso para generar pagos recurrentes'; end if;
  ini:=to_date(p_periodo||'-01','YYYY-MM-DD');
  fin:=(ini+interval '1 month'-interval '1 day')::date;
  meses_periodo:=extract(year from ini)::int*12+extract(month from ini)::int;
  for r in select x.* from plone27_recurrentes x
           where x.entidad=ent and x.activo and x.desde<=fin and (x.hasta is null or x.hasta>=ini) order by x.id loop
    meses_desde:=extract(year from r.desde)::int*12+extract(month from r.desde)::int;
    if (meses_periodo-meses_desde)<0 or (meses_periodo-meses_desde)%r.periodicidad_meses<>0 then continue; end if;
    if exists(select 1 from plone27_recurrentes_generados rg where rg.recurrente=r.id and rg.periodo=p_periodo) then continue; end if;
    insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,origen,beneficiario,propuesto_por,fecha)
      values(ent,r.unidad,extract(year from ini)::int,r.importe,r.concepto,'manual',r.beneficiario,r.autorizada_por,ini)
      returning plone27_gastos.id into gid;
    insert into plone27_recurrentes_generados(recurrente,periodo,gasto) values(r.id,p_periodo,gid);
    n:=n+1;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'recurrentes_generar','account',ent::text,jsonb_build_object('periodo',p_periodo,'propuestas',n));
  return n;
end $$;

create or replace function plone27_convocatoria_crear(p_bank uuid,p_cip text,p_actor uuid,p_nombre text,p_importe numeric,p_desde date,p_hasta date) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; cid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para abrir convocatorias'; end if;
  insert into plone27_convocatorias(entidad,nombre,importe,desde,hasta) values(ent,p_nombre,p_importe,p_desde,p_hasta)
    returning plone27_convocatorias.id into cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'convocatoria_crear','account',ent::text,jsonb_build_object('convocatoria',cid,'importe',p_importe));
  return cid;
end $$;

-- Solicitud de una unidad. Solo si la entidad tiene activadas las solicitudes.
create or replace function plone27_solicitud_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_tipo text,p_importe numeric,p_referencia uuid,p_nueva_fecha date,p_justificacion text,p_convocatoria uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; activas boolean; sid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  select e.solicitudes_activas into activas from plone27_entidades e where e.account_id=ent;
  if not activas then raise exception 'Las solicitudes no están activadas en esta entidad'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  if not plone27_puede(p_actor,p_unidad,'proponer',p_importe) then raise exception 'Sin permiso para solicitar en esta unidad'; end if;
  if p_tipo='ampliacion' and coalesce(p_importe,0)<=0 then raise exception 'La ampliación necesita un importe'; end if;
  if p_tipo='reserva_extra' and (p_referencia is null or coalesce(p_importe,0)<=0) then raise exception 'La reserva extra necesita un fondo y un importe'; end if;
  if p_tipo='prorroga' and (p_nueva_fecha is null or p_referencia is null) then raise exception 'La prórroga necesita la fecha nueva y el elemento a prorrogar'; end if;
  if p_tipo='financiacion' and p_convocatoria is null then raise exception 'La financiación necesita una convocatoria'; end if;
  insert into plone27_solicitudes_unidad(entidad,unidad,tipo,importe,referencia,convocatoria,nueva_fecha,justificacion,solicitada_por)
    values(ent,p_unidad,p_tipo,p_importe,p_referencia,p_convocatoria,p_nueva_fecha,p_justificacion,p_actor)
    returning plone27_solicitudes_unidad.id into sid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'solicitud_crear','unidad',p_unidad::text,jsonb_build_object('solicitud',sid,'tipo',p_tipo));
  return sid;
end $$;

-- Resolver una solicitud: quien decide necesita permiso de presupuesto y no puede ser quien la pidió.
create or replace function plone27_solicitud_resolver(p_bank uuid,p_solicitud uuid,p_actor uuid,p_decision text,p_resolucion text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_solicitudes_unidad; cip text; asig numeric; conv plone27_convocatorias; conc numeric; ejer int; begin
  select * into s from plone27_solicitudes_unidad where id=p_solicitud for update;
  if s.id is null or not exists(select 1 from plone27_entidades e where e.account_id=s.entidad and e.bank_id=p_bank) then
    raise exception 'Solicitud no encontrada';
  end if;
  if s.estado<>'pendiente' then raise exception 'La solicitud ya está resuelta'; end if;
  if p_actor=s.solicitada_por then raise exception 'Nadie puede resolver su propia solicitud'; end if;
  if p_decision not in('concedida','denegada') then raise exception 'Decisión no válida'; end if;
  if not plone27_puede(p_actor,s.unidad,'presupuestar',s.importe) then raise exception 'Sin permiso para resolver solicitudes de esta unidad'; end if;
  ejer:=extract(year from current_date)::int;
  if p_decision='concedida' then
    select e.cip into cip from plone27_entidades e where e.account_id=s.entidad;
    if s.tipo='ampliacion' then
      select coalesce((select p.anual from plone27_presupuestos p where p.unidad=s.unidad and p.ejercicio=ejer),0) into asig;
      perform plone27_presupuesto_fijar(p_bank,cip,p_actor,s.unidad,ejer,asig+s.importe);
    elsif s.tipo='reserva_extra' then
      update plone27_fondos set importe=importe+s.importe where id=s.referencia and unidad=s.unidad;
      if not found then raise exception 'El fondo no pertenece a la unidad de la solicitud'; end if;
    elsif s.tipo='prorroga' then
      if exists(select 1 from plone27_convocatorias c where c.id=s.referencia and c.entidad=s.entidad) then
        update plone27_convocatorias set hasta=s.nueva_fecha where id=s.referencia;
      elsif exists(select 1 from plone27_recurrentes r where r.id=s.referencia and r.entidad=s.entidad) then
        update plone27_recurrentes set hasta=s.nueva_fecha where id=s.referencia;
      else
        raise exception 'El elemento a prorrogar no existe en la entidad';
      end if;
    elsif s.tipo='financiacion' then
      select * into conv from plone27_convocatorias where id=s.convocatoria for update;
      if conv.id is null or conv.estado<>'abierta' then raise exception 'La convocatoria no está abierta'; end if;
      select coalesce(sum(x.importe),0) into conc from plone27_solicitudes_unidad x
        where x.convocatoria=conv.id and x.estado='concedida';
      if conc+s.importe>conv.importe then raise exception 'La convocatoria no tiene fondos suficientes (disponible: %)', conv.importe-conc; end if;
      select coalesce((select p.anual from plone27_presupuestos p where p.unidad=s.unidad and p.ejercicio=ejer),0) into asig;
      perform plone27_presupuesto_fijar(p_bank,cip,p_actor,s.unidad,ejer,asig+s.importe);
    end if;
  end if;
  update plone27_solicitudes_unidad set estado=p_decision, resuelta_por=p_actor, resolucion=p_resolucion, resuelta=now() where id=p_solicitud;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'solicitud_resuelta','unidad',s.unidad::text,jsonb_build_object('solicitud',p_solicitud,'decision',p_decision));
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
