-- Placeta One · 0059 · La nómina paga salario y complementos vigentes del periodo; recibos del periodo para NEXE.
-- Requiere 0058. Idempotente. NO ejecutado en PostgreSQL.

-- Nómina del periodo: salario (retribución) + complementos de actividad asignados y vigentes en el periodo.
-- Cada pago es idempotente por referencia y periodo. Quien asigna un complemento no puede ejecutar la nómina.
create or replace function plone27_nomina_periodo(p_bank uuid,p_cip text,p_actor uuid,p_periodo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ini date; fin date; ejer int; r plone27_retribuciones; cc record; comp plone27_complementos;
  unidad uuid; ben uuid; ref text; gid uuid; tx uuid; n int:=0; total numeric:=0; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'ejecutar') then raise exception 'Sin permiso para ejecutar nóminas'; end if;
  ini:=to_date(p_periodo||'-01','YYYY-MM-DD');
  fin:=(ini+interval '1 month'-interval '1 day')::date;
  ejer:=extract(year from ini)::int;
  -- 1) Salario
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
  -- 2) Complementos de actividad vigentes en el periodo
  for cc in select x.* from plone27_complementos_contrato x
            join plone27_retribuciones rr on rr.id=x.retribucion
            where rr.entidad=ent and x.desde<=fin and (x.hasta is null or x.hasta>=ini) order by x.id loop
    select * into r from plone27_retribuciones where id=cc.retribucion;
    select * into comp from plone27_complementos where id=cc.complemento;
    ref:='complemento:'||cc.id::text;
    continue when exists(select 1 from plone27_nominas_pagadas np where np.persona=r.persona and np.periodo=p_periodo and np.referencia=ref);
    unidad:=plone27_puesto_de(r.persona,ent);
    if unidad is null then raise exception 'Una persona con complemento no tiene puesto en la entidad'; end if;
    ben:=plone27_cuenta_titular(r.persona,p_bank);
    if ben is null then raise exception 'Una persona con complemento no tiene cuenta en la entidad'; end if;
    if cc.asignado_por=p_actor then raise exception 'Quien asigna un complemento no puede ejecutar la nómina'; end if;
    perform plone27_verificar_presupuesto(unidad,ejer,cc.importe);
    tx:=plone27_transfer('nomina:'||p_periodo||':c:'||cc.id::text,ent,ben,cc.importe,'Complemento '||comp.codigo||' '||p_periodo,p_actor);
    insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,origen,beneficiario,propuesto_por,pagado_por,estado,tx,resuelto)
      values(ent,unidad,ejer,cc.importe,comp.nombre||' '||p_periodo,'retribucion',ben,cc.asignado_por,p_actor,'pagado',tx,now())
      returning plone27_gastos.id into gid;
    insert into plone27_nominas_pagadas(persona,periodo,referencia,importe,gasto,tx)
      values(r.persona,p_periodo,ref,cc.importe,gid,tx);
    n:=n+1; total:=total+cc.importe;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'nomina_periodo','account',ent::text,jsonb_build_object('periodo',p_periodo,'pagos',n,'total',total));
  return jsonb_build_object('periodo',p_periodo,'pagos',n,'total',total);
end $$;

-- Recibos pagados del periodo: por persona, salario y complementos con su transferencia (para NEXE)
create or replace function plone27_bk_recibos_periodo(p_bank uuid,p_cip text,p_periodo text,p_dip text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.persona, x.tipo),'[]'::jsonb) from (
    select p.dip as persona,
      case when np.referencia like 'retribucion:%' then 'salario' else 'complemento' end as tipo,
      np.referencia, g.concepto, np.importe, np.tx, np.periodo
    from plone27_nominas_pagadas np
    join plone27_personas p on p.id=np.persona
    join plone27_gastos g on g.id=np.gasto
    where g.entidad=ent and np.periodo=p_periodo and (p_dip is null or p.dip=p_dip)) x);
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
