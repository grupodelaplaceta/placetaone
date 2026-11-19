-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0043 · Idempotencia del cobro de deudas, plazos configurables y permiso de reclamación
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0042.
-- ATENCIÓN: no ejecutada en PostgreSQL. Probar con verificacion/pruebas_db.sql en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0043 · Corrección de idempotencia en el cobro de deudas, parámetros configurables de disputas.
-- Requiere 0042. Idempotente. NO ejecutado en PostgreSQL: probar con verificacion/pruebas_db.sql antes de producción.

-- ---------- Parámetros configurables (plazos y umbrales) ----------
create table if not exists plone27_parametros(
  clave text primary key,
  valor numeric(18,4) not null,
  actualizado timestamptz not null default now(),
  actor uuid);
insert into plone27_parametros(clave,valor) values
  ('disputa.plazo_apertura_dias',60),
  ('disputa.plazo_resolucion_dias',30),
  ('disputa.umbral_doble_aprobacion',1000)
on conflict(clave) do nothing;

create or replace function plone27_parametro(p_clave text) returns numeric
language sql stable security definer set search_path=public as $$
  select valor from plone27_parametros where clave=p_clave $$;

create or replace function plone27_parametro_set(p_clave text,p_valor numeric,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_clave not in('disputa.plazo_apertura_dias','disputa.plazo_resolucion_dias','disputa.umbral_doble_aprobacion') then
    raise exception 'Parámetro no válido';
  end if;
  if p_clave='disputa.plazo_apertura_dias' and (p_valor<1 or p_valor>365) then raise exception 'Plazo de apertura entre 1 y 365 días'; end if;
  if p_clave='disputa.plazo_resolucion_dias' and (p_valor<1 or p_valor>180) then raise exception 'Plazo de resolución entre 1 y 180 días'; end if;
  if p_clave='disputa.umbral_doble_aprobacion' and (p_valor<0 or p_valor>1000000) then raise exception 'Umbral entre 0 y 1.000.000 Pz'; end if;
  insert into plone27_parametros(clave,valor,actor) values(p_clave,p_valor,p_actor)
    on conflict(clave) do update set valor=excluded.valor, actualizado=now(), actor=excluded.actor;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'parametro_set','parametro',p_clave,jsonb_build_object('valor',p_valor));
end $$;

-- ---------- Cobro de deuda: IDEMPOTENTE ----------
-- Una clave repetida con los mismos datos devuelve la transacción original y NO vuelve a sumar el pago a la deuda.
-- Una clave repetida con datos distintos falla.
create or replace function plone27_debt_pay(p_key text,p_debt uuid,p_amount numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; tx uuid; ob uuid; db uuid; h text; viejo text; begin
  select * into d from plone27_debts where id=p_debt for update;
  if d.id is null then raise exception 'Deuda no encontrada'; end if;
  if d.creditor_account is null then raise exception 'La deuda no tiene acreedor'; end if;
  -- misma huella que calcula plone27_post para la transferencia equivalente
  h:=md5('transfer'||jsonb_build_array(
      jsonb_build_object('account',d.account_id,'dir','debit','amount',p_amount),
      jsonb_build_object('account',d.creditor_account,'dir','credit','amount',p_amount))::text);
  select t.id, t.req_hash into tx, viejo from plone27_transactions t where t.idempotency_key=p_key;
  if tx is not null then
    if viejo is not null and viejo<>h then raise exception 'Idempotency-Key reutilizada con datos distintos'; end if;
    return tx;
  end if;
  if d.disputed then raise exception 'Deuda en disputa: no se cobra'; end if;
  if d.paid+p_amount>d.principal+d.authorized_charges then raise exception 'Excede la deuda'; end if;
  tx:=plone27_transfer(p_key,d.account_id,d.creditor_account,p_amount,'Deuda '||d.ref,p_actor);
  update plone27_debts set paid=paid+p_amount where id=p_debt;
  select a.bank_id into ob from plone27_accounts a where a.id=d.account_id;
  select a.bank_id into db from plone27_accounts a where a.id=d.creditor_account;
  if ob is not null and db is not null and ob<>db then perform plone27_registrar_op(ob,db,p_amount,'deuda:'||tx::text); end if;
  return tx;
end $$;

-- ---------- Reclamación con plazos desde parámetros ----------
create or replace function plone27_user_disputa_abrir(p_user uuid,p_bank uuid,p_debt uuid,p_monto numeric,p_motivo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; did uuid; begin
  select * into d from plone27_debts where id=p_debt for update;
  if d.id is null or not exists(select 1 from plone27_accounts a where a.id=d.account_id and a.bank_id=p_bank) then
    raise exception 'Deuda no encontrada';
  end if;
  if not plone27_user_can(p_user,d.account_id,true,p_bank) then raise exception 'No puedes reclamar sobre esta deuda'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'Explica el motivo con al menos 10 caracteres'; end if;
  if p_monto is null or p_monto<=0 or p_monto>coalesce(d.paid,0) then
    raise exception 'Solo puedes reclamar hasta lo pagado (% Pz)', coalesce(d.paid,0);
  end if;
  if current_date>coalesce(d.due_date,current_date)+plone27_parametro('disputa.plazo_apertura_dias')::int then
    raise exception 'El plazo para reclamar ha vencido';
  end if;
  if exists(select 1 from plone27_disputas x where x.debt_id=p_debt and x.estado='abierta') then
    raise exception 'Ya hay una reclamación abierta para esta deuda';
  end if;
  insert into plone27_disputas(debt_id,account_id,monto_reclamado,motivo,abierta_por,plazo_resolucion)
    values(p_debt,d.account_id,p_monto,p_motivo,p_user,current_date+plone27_parametro('disputa.plazo_resolucion_dias')::int)
    returning plone27_disputas.id into did;
  update plone27_debts set disputed=true where id=p_debt;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_user,'disputa_abierta','deuda',p_debt::text,jsonb_build_object('monto',p_monto));
  return did; end $$;

-- ---------- Resolución con umbral desde parámetros ----------
create or replace function plone27_disputa_resolver(p_id uuid,p_decision text,p_monto numeric,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare x plone27_disputas; d plone27_debts; m numeric; cb uuid; ob uuid; tx uuid; begin
  select * into x from plone27_disputas where id=p_id for update;
  if x.id is null or x.estado<>'abierta' then raise exception 'Reclamación no encontrada o ya resuelta'; end if;
  select * into d from plone27_debts where id=x.debt_id for update;
  if p_decision='rechazada' then
    update plone27_disputas set estado='rechazada', resuelta_por=p_actor, resuelta=now() where id=p_id;
    update plone27_debts set disputed=false where id=x.debt_id;
    insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'disputa_rechazada','disputa',p_id::text,'{}'::jsonb);
    return jsonb_build_object('estado','rechazada');
  end if;
  if p_decision<>'devolucion' then raise exception 'Decisión no válida'; end if;
  m:=coalesce(p_monto,x.monto_reclamado);
  if m<=0 or m>x.monto_reclamado or m>coalesce(d.paid,0) then raise exception 'Importe de devolución no válido'; end if;
  if d.creditor_account is null then raise exception 'La deuda no tiene acreedor'; end if;
  if m>plone27_parametro('disputa.umbral_doble_aprobacion') then
    if x.aprobada_1 is null then
      update plone27_disputas set aprobada_1=p_actor where id=p_id;
      return jsonb_build_object('estado','pendiente_segunda_aprobacion');
    end if;
    if x.aprobada_1=p_actor then raise exception 'Otra persona debe aprobar esta devolución'; end if;
    update plone27_disputas set aprobada_2=p_actor where id=p_id;
  end if;
  if plone27_available(d.creditor_account)<m then raise exception 'El acreedor no tiene saldo para la devolución'; end if;
  tx:=plone27_transfer('disp:'||p_id::text,d.creditor_account,d.account_id,m,'Devolución por reclamación',p_actor);
  select a.bank_id into cb from plone27_accounts a where a.id=d.creditor_account;
  select a.bank_id into ob from plone27_accounts a where a.id=d.account_id;
  if cb is not null and ob is not null and cb<>ob then perform plone27_registrar_op(cb,ob,m,'devolucion:'||tx::text); end if;
  update plone27_debts set paid=paid-m, disputed=false where id=x.debt_id;
  update plone27_disputas set estado='devuelta', monto_devuelto=m, resuelta_por=p_actor, resuelta=now() where id=p_id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'disputa_devuelta','disputa',p_id::text,jsonb_build_object('monto',m));
  return jsonb_build_object('estado','devuelta','transaccion',tx,'monto',m); end $$;

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


do $$ begin raise notice 'Actualización 0043 aplicada correctamente.'; end $$;

commit;
