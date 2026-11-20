begin;
-- Placeta One · 0065 · Lo recuperado de una deuda por reversión se vuelve a autorizar, según la convocatoria.
-- Disparador diferido: se ejecuta al cerrar la transacción, cuando el cobro ya está en el programa. Requiere 0064. Idempotente. NO ejecutado en PostgreSQL.

alter table plone27_convocatorias add column if not exists reautoriza_recuperados boolean not null default true;
alter table plone27_grant_reversiones add column if not exists reautorizado numeric(18,2) not null default 0;

-- Decide por convocatoria si lo recuperado se vuelve a autorizar
create or replace function plone27_convocatoria_reautorizacion_fijar(p_conv uuid,p_valor boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cv plone27_convocatorias; begin
  select * into cv from plone27_convocatorias where id=p_conv;
  if cv.id is null then raise exception 'Convocatoria no encontrada'; end if;
  if not plone27_es_admin(p_actor) and not plone27_tiene_en_entidad(p_actor,cv.entidad,'presupuestar') then raise exception 'Sin permiso para cambiar la convocatoria'; end if;
  update plone27_convocatorias set reautoriza_recuperados=p_valor where id=p_conv;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'convocatoria_reautorizacion','convocatoria',p_conv::text,jsonb_build_object('valor',p_valor)); end $$;

-- Al cobrarse una deuda de reversión (al cerrar la transacción): se reautoriza si la convocatoria lo permite
create or replace function plone27_trg_debt_reautoriza() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rv plone27_grant_reversiones; g plone27_grants; pr plone27_grant_programs; cv plone27_convocatorias; inc numeric; motivo text; begin
  inc:=new.paid-old.paid;
  if inc<=0 then return new; end if;
  select * into rv from plone27_grant_reversiones where deuda_id=new.id limit 1;
  if rv.id is null then return new; end if;
  select * into g from plone27_grants where id=rv.grant_id for update;
  select * into pr from plone27_grant_programs where id=g.program_id;
  motivo:=null;
  if g.estado<>'activa' or (g.caduca is not null and g.caduca<current_date) then motivo:='subvención no activa o caducada';
  elsif g.convocatoria is not null then
    select * into cv from plone27_convocatorias where id=g.convocatoria;
    if cv.estado<>'abierta' then motivo:='convocatoria cerrada';
    elsif not cv.reautoriza_recuperados then motivo:='la convocatoria no reautoriza lo recuperado';
    end if;
  end if;
  if motivo is null and plone27_available(pr.funding_account)<inc then motivo:='fondos insuficientes en el programa'; end if;
  if motivo is not null then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(null,'reautorizacion_omitida','grant',g.id::text,jsonb_build_object('importe',inc,'motivo',motivo));
    return new;
  end if;
  if g.reserva is not null and exists(select 1 from plone27_reservations where id=g.reserva and status='active') then
    update plone27_reservations set amount=amount+inc where id=g.reserva;
  else
    update plone27_grants set reserva=plone27_reserve(pr.funding_account,inc,'Reautorización por deuda recuperada: '||pr.name,null) where id=g.id;
  end if;
  update plone27_grant_reversiones set reautorizado=reautorizado+inc where id=rv.id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(null,'reautorizacion','grant',g.id::text,jsonb_build_object('importe',inc));
  return new; end $$;

drop trigger if exists trg_debt_reautoriza on plone27_debts;
create constraint trigger trg_debt_reautoriza after update of paid on plone27_debts
  deferrable initially deferred for each row execute function plone27_trg_debt_reautoriza();

-- Informe: incluye lo reautorizado de cada reversión
create or replace function plone27_grant_informe(p_grant uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; pr plone27_grant_programs; ben text; begin
  select * into g from plone27_grants where id=p_grant;
  if g.id is null then raise exception 'Subvención no encontrada'; end if;
  select * into pr from plone27_grant_programs where id=g.program_id;
  select a.iban into ben from plone27_accounts a where a.id=g.beneficiary_account;
  return jsonb_build_object(
    'subvencion',g.id,'programa',pr.name,'tipo',pr.kind,'beneficiario_iban',ben,
    'concedido',g.granted,'aprobado',g.approved,'pagado',g.paid,'pendiente_de_pago',g.granted-g.paid,
    'estado',g.estado,'caduca',g.caduca,
    'justificaciones',coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'factura',j.invoice_ref,'importe',j.amount,'estado',j.status,'transferencia',j.reembolso_tx) order by j.id)
                                from plone27_justifications j where j.grant_id=p_grant),'[]'::jsonb),
    'reversiones',coalesce((select jsonb_agg(jsonb_build_object('importe',r.importe,'devuelto',r.devuelto,'deuda',r.deuda,'reautorizado',r.reautorizado,'motivo',r.motivo,'fecha',r.creada) order by r.creada)
                            from plone27_grant_reversiones r where r.grant_id=p_grant),'[]'::jsonb),
    'generado',now()); end $$;

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

do $$ begin raise notice 'Actualización 0065 aplicada correctamente.'; end $$;

commit;
