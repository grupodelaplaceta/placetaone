-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0045 · Ficha de empresa: entidad institucional, organigrama, presupuesto y nóminas
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0044.
-- ATENCIÓN: no ejecutada en PostgreSQL. Probar en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0045 · Ficha de empresa: vínculo con la entidad institucional, organigrama, presupuesto por departamento
-- y nóminas pagadas. Requiere 0044. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

alter table plone27_empresas add column if not exists entidad_cip text references plone27_entidades(cip);
create unique index if not exists plone27_empresa_entidad_ux on plone27_empresas(entidad_cip) where entidad_cip is not null;

-- Vincula la entidad institucional a la empresa. Solo un titular activo de la empresa puede hacerlo.
create or replace function plone27_empresa_vincular_entidad(p_bank uuid,p_empresa uuid,p_cip text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  if not exists(select 1 from plone27_entidades x where x.cip=p_cip and x.bank_id=p_bank and x.activa) then
    raise exception 'Entidad institucional no encontrada o inactiva en tu entidad';
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=p_cip and o.id<>p_empresa) then
    raise exception 'Esa entidad ya está vinculada a otra empresa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede vincular una entidad';
  end if;
  update plone27_empresas set entidad_cip=p_cip where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_vincular_entidad','empresa',p_empresa::text,jsonb_build_object('cip',p_cip));
end $$;

-- Ficha completa. Ejercicio = año en curso. Pagado = gastos pagados; comprometido = propuestos o aprobados.
create or replace function plone27_empresa_ficha(p_bank uuid,p_empresa uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; ent plone27_entidades; ej int := extract(year from current_date)::int; r jsonb; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null then return null; end if;
  if e.entidad_cip is null then
    return jsonb_build_object('empresa',jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado),
      'entidad',null,'ejercicio',ej);
  end if;
  select * into ent from plone27_entidades where cip=e.entidad_cip;
  select jsonb_build_object(
    'empresa',jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado),
    'entidad',jsonb_build_object('cip',ent.cip,'nombre',ent.nombre,'activa',ent.activa),
    'ejercicio',ej,
    'organigrama',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'padre',u.padre,'tipo',u.tipo,'nombre',u.nombre,'codigo',u.codigo,'activa',u.activa) order by u.nombre),'[]'::jsonb)
                   from plone27_unidades u where u.entidad=ent.account_id),
    'departamentos',(select coalesce(jsonb_agg(to_jsonb(x) order by x.nombre),'[]'::jsonb) from (
        select u.id, u.nombre, u.tipo,
          coalesce((select sum(p.anual) from plone27_presupuestos p where p.unidad=u.id and p.ejercicio=ej),0) as presupuesto_anual,
          coalesce((select sum(g.importe) from plone27_gastos g where g.unidad=u.id and g.ejercicio=ej and g.estado='pagado'),0) as pagado,
          coalesce((select sum(g.importe) from plone27_gastos g where g.unidad=u.id and g.ejercicio=ej and g.estado in('propuesto','aprobado')),0) as comprometido
        from plone27_unidades u where u.entidad=ent.account_id) x),
    'nominas',(select coalesce(jsonb_agg(to_jsonb(x) order by x.periodo desc),'[]'::jsonb) from (
        select to_char(g.fecha,'YYYY-MM') as periodo, count(*) as pagos, sum(n.importe) as total
        from plone27_nominas_pagadas n join plone27_gastos g on g.id=n.gasto
        where g.entidad=ent.account_id group by to_char(g.fecha,'YYYY-MM')) x)
  ) into r;
  return r; end $$;

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


do $$ begin raise notice 'Actualización 0045 aplicada correctamente.'; end $$;

commit;
