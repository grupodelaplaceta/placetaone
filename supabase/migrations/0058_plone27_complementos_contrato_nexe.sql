-- Placeta One · 0058 · Complementos de actividad asignables a un contrato, y conceptos por periodo para NEXE.
-- Requiere 0057. Idempotente. NO ejecutado en PostgreSQL. No modifica el motor de nóminas existente.

-- Catálogo de complementos de cada entidad
create table if not exists plone27_complementos(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  codigo text not null check(codigo ~ '^[A-Z0-9_]{2,20}$'),
  nombre text not null check(length(nombre) between 3 and 120),
  tipo text not null default 'fijo' check(tipo in('fijo','variable')),
  importe_base numeric(18,2) check(importe_base is null or importe_base>=0),
  activo boolean not null default true,
  creado timestamptz not null default now(),
  unique(entidad,codigo));

-- Asignación de un complemento a un contrato (retribución), con vigencia
create table if not exists plone27_complementos_contrato(
  id uuid primary key default gen_random_uuid(),
  retribucion uuid not null references plone27_retribuciones(id),
  complemento uuid not null references plone27_complementos(id),
  importe numeric(18,2) not null check(importe>0),
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  asignado_por uuid,
  creado timestamptz not null default now(),
  check(hasta is null or hasta>=desde));
create unique index if not exists plone27_complemento_activo_ux on plone27_complementos_contrato(retribucion,complemento) where hasta is null;

create or replace function plone27_bk_complemento_crear(p_bank uuid,p_cip text,p_actor uuid,p_codigo text,p_nombre text,p_tipo text,p_importe numeric) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; cid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'retribuir') then raise exception 'Sin permiso para retribuir en esta entidad'; end if;
  if p_tipo not in('fijo','variable') then raise exception 'Tipo de complemento no válido (fijo o variable)'; end if;
  insert into plone27_complementos(entidad,codigo,nombre,tipo,importe_base) values(ent,upper(p_codigo),p_nombre,p_tipo,p_importe)
    returning plone27_complementos.id into cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'complemento_crear','complemento',cid::text,jsonb_build_object('codigo',upper(p_codigo)));
  return cid; end $$;

create or replace function plone27_bk_complementos(p_bank uuid,p_cip text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.codigo),'[]'::jsonb) from (
    select c.id, c.codigo, c.nombre, c.tipo, c.importe_base, c.activo from plone27_complementos c where c.entidad=ent) x);
end $$;

create or replace function plone27_bk_complemento_asignar(p_bank uuid,p_cip text,p_actor uuid,p_retribucion uuid,p_complemento uuid,
    p_importe numeric,p_desde date,p_hasta date,p_motivo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; c plone27_complementos; r plone27_retribuciones; imp numeric; aid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'retribuir') then raise exception 'Sin permiso para retribuir en esta entidad'; end if;
  select * into r from plone27_retribuciones where id=p_retribucion and entidad=ent;
  if r.id is null then raise exception 'Contrato (retribución) no encontrado en la entidad'; end if;
  select * into c from plone27_complementos where id=p_complemento and entidad=ent and activo;
  if c.id is null then raise exception 'Complemento no encontrado o inactivo'; end if;
  imp:=coalesce(p_importe,c.importe_base);
  if imp is null or imp<=0 then raise exception 'Indica el importe del complemento'; end if;
  if coalesce(length(p_motivo),0)<5 then raise exception 'El motivo debe tener al menos 5 caracteres'; end if;
  if exists(select 1 from plone27_complementos_contrato cc where cc.retribucion=p_retribucion and cc.complemento=p_complemento and cc.hasta is null) then
    raise exception 'Este complemento ya está asignado a ese contrato: retíralo antes';
  end if;
  insert into plone27_complementos_contrato(retribucion,complemento,importe,desde,hasta,motivo,asignado_por)
    values(p_retribucion,p_complemento,imp,coalesce(p_desde,current_date),p_hasta,p_motivo,p_actor)
    returning plone27_complementos_contrato.id into aid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'complemento_asignar','asignacion',aid::text,jsonb_build_object('importe',imp));
  return aid; end $$;

create or replace function plone27_bk_complemento_retirar(p_bank uuid,p_cip text,p_actor uuid,p_asignacion uuid,p_hasta date) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; n int; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'retribuir') then raise exception 'Sin permiso para retribuir en esta entidad'; end if;
  with x as(update plone27_complementos_contrato cc set hasta=coalesce(p_hasta,current_date)
            from plone27_retribuciones r
            where cc.id=p_asignacion and cc.hasta is null and r.id=cc.retribucion and r.entidad=ent returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Asignación no encontrada o ya retirada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'complemento_retirar','asignacion',p_asignacion::text,jsonb_build_object('hasta',coalesce(p_hasta,current_date)));
end $$;

-- Conceptos de un periodo (AAAA-MM): lo que NEXE necesita para emitir la nómina
create or replace function plone27_bk_conceptos_periodo(p_bank uuid,p_cip text,p_periodo text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ini date; fin date; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  ini:=to_date(p_periodo||'-01','YYYY-MM-DD');
  fin:=(ini + interval '1 month' - interval '1 day')::date;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.persona, x.tipo, x.concepto),'[]'::jsonb) from (
    select p.dip as persona, 'retribucion'::text as tipo, null::text as codigo, r.concepto as concepto, r.importe as importe, p_periodo::text as periodo
      from plone27_retribuciones r join plone27_personas p on p.id=r.persona
      where r.entidad=ent and r.desde<=fin and (r.hasta is null or r.hasta>=ini)
    union all
    select p.dip, 'complemento'::text, c.codigo, c.nombre, cc.importe, p_periodo::text
      from plone27_complementos_contrato cc
      join plone27_retribuciones r on r.id=cc.retribucion
      join plone27_complementos c on c.id=cc.complemento
      join plone27_personas p on p.id=r.persona
      where r.entidad=ent and cc.desde<=fin and (cc.hasta is null or cc.hasta>=ini)
  ) x);
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
