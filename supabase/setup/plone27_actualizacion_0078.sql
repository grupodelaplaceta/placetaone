begin;
-- Placeta One · 0078 · Anular o modificar una deuda: solo la Junta, con justificación y la referencia
-- del acuerdo de votación de esa actuación. Cada referencia de acuerdo solo puede usarse una vez.
-- Requiere 0077. Idempotente. NO ejecutado en PostgreSQL.

create table if not exists plone27_deuda_actuaciones(
  id uuid primary key default gen_random_uuid(),
  debt uuid not null references plone27_debts(id),
  tipo text not null check(tipo in('anulacion','modificacion')),
  pendiente_anterior numeric(18,2) not null,
  pendiente_nuevo numeric(18,2) not null check(pendiente_nuevo>=0),
  justificacion text not null check(length(justificacion)>=30),
  referencia_acuerdo text not null unique check(length(referencia_acuerdo)>=5),
  actor uuid not null,
  creada timestamptz not null default now());

-- Anular: el pendiente pasa a cero; lo ya pagado se mantiene
create or replace function plone27_deuda_anular(p_debt uuid,p_justificacion text,p_referencia text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; pend numeric; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta anula deudas'; end if;
  if coalesce(length(p_justificacion),0)<30 then raise exception 'La justificación debe tener al menos 30 caracteres'; end if;
  if coalesce(length(p_referencia),0)<5 then raise exception 'Indica la referencia del acuerdo de votación de esta actuación'; end if;
  select * into d from plone27_debts where id=p_debt for update;
  if d.id is null then raise exception 'Deuda no encontrada'; end if;
  pend:=d.principal+coalesce(d.authorized_charges,0)-coalesce(d.paid,0);
  if pend<=0 then raise exception 'La deuda ya no tiene importe pendiente'; end if;
  update plone27_debts set principal=coalesce(paid,0), authorized_charges=0 where id=p_debt;
  insert into plone27_deuda_actuaciones(debt,tipo,pendiente_anterior,pendiente_nuevo,justificacion,referencia_acuerdo,actor)
    values(p_debt,'anulacion',pend,0,p_justificacion,p_referencia,p_actor);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'deuda_anular','deuda',p_debt::text,jsonb_build_object('pendiente_anterior',pend,'acuerdo',p_referencia));
  return jsonb_build_object('anulada',true,'pendiente_anterior',pend); end $$;

-- Modificar: fija un nuevo importe pendiente; lo ya pagado se mantiene
create or replace function plone27_deuda_modificar(p_debt uuid,p_nuevo numeric,p_justificacion text,p_referencia text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; pend numeric; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta modifica deudas'; end if;
  if coalesce(length(p_justificacion),0)<30 then raise exception 'La justificación debe tener al menos 30 caracteres'; end if;
  if coalesce(length(p_referencia),0)<5 then raise exception 'Indica la referencia del acuerdo de votación de esta actuación'; end if;
  if p_nuevo is null or p_nuevo<0 then raise exception 'El nuevo importe pendiente no puede ser negativo'; end if;
  select * into d from plone27_debts where id=p_debt for update;
  if d.id is null then raise exception 'Deuda no encontrada'; end if;
  pend:=d.principal+coalesce(d.authorized_charges,0)-coalesce(d.paid,0);
  if pend<=0 then raise exception 'La deuda ya no tiene importe pendiente'; end if;
  if p_nuevo=pend then raise exception 'El nuevo importe es igual al actual'; end if;
  update plone27_debts set principal=coalesce(paid,0)+p_nuevo, authorized_charges=0 where id=p_debt;
  insert into plone27_deuda_actuaciones(debt,tipo,pendiente_anterior,pendiente_nuevo,justificacion,referencia_acuerdo,actor)
    values(p_debt,'modificacion',pend,p_nuevo,p_justificacion,p_referencia,p_actor);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'deuda_modificar','deuda',p_debt::text,jsonb_build_object('pendiente_anterior',pend,'pendiente_nuevo',p_nuevo,'acuerdo',p_referencia));
  return jsonb_build_object('modificada',true,'pendiente_anterior',pend,'pendiente_nuevo',p_nuevo); end $$;

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

do $$ begin raise notice 'Actualización 0078 aplicada correctamente.'; end $$;

commit;
