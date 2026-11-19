-- Placeta One · 0042 · Disputas de deudas, deudas en la API del usuario y bucket de logos.
-- Requiere 0041. Idempotente. NO ejecutado en PostgreSQL: probar en una base de pruebas.

-- ---------- Disputas ----------
create table if not exists plone27_disputas(
  id uuid primary key default gen_random_uuid(),
  debt_id uuid not null references plone27_debts(id),
  account_id uuid not null references plone27_accounts,
  monto_reclamado numeric(18,2) not null check(monto_reclamado>0),
  motivo text not null check(length(motivo)>=10),
  estado text not null default 'abierta' check(estado in('abierta','devuelta','rechazada')),
  monto_devuelto numeric(18,2) not null default 0 check(monto_devuelto>=0),
  abierta_por uuid not null,
  aprobada_1 uuid,
  aprobada_2 uuid,
  resuelta_por uuid,
  plazo_resolucion date not null,
  creada timestamptz not null default now(),
  resuelta timestamptz);
create unique index if not exists plone27_disputa_abierta_ux on plone27_disputas(debt_id) where estado='abierta';

-- Lo que el titular de la cuenta puede ver de sus deudas (solo cuentas donde tiene acceso)
create or replace function plone27_user_debts(p_user uuid,p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.vencimiento, x.id),'[]'::jsonb) from (
    select d.id, d.ref, a.iban as cuenta, ca.iban as acreedor, d.principal, d.authorized_charges as cargos_autorizados,
      d.paid as pagado, (d.principal+coalesce(d.authorized_charges,0)-coalesce(d.paid,0)) as pendiente,
      d.due_date as vencimiento, d.disputed as en_disputa, d.reason as concepto
    from plone27_debts d
    join plone27_accounts a on a.id=d.account_id
    left join plone27_accounts ca on ca.id=d.creditor_account
    where a.bank_id=p_bank and plone27_user_can(p_user,a.id,false,p_bank)) x $$;

-- Pago de una deuda por el titular (con permiso de escritura en la cuenta deudora)
create or replace function plone27_user_debt_pay(p_user uuid,p_bank uuid,p_debt uuid,p_amount numeric,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; begin
  select * into d from plone27_debts where id=p_debt;
  if d.id is null or not exists(select 1 from plone27_accounts a where a.id=d.account_id and a.bank_id=p_bank) then
    raise exception 'Deuda no encontrada';
  end if;
  if not plone27_user_can(p_user,d.account_id,true,p_bank) then raise exception 'No puedes pagar esta deuda desde esta cuenta'; end if;
  return plone27_debt_pay(p_key,p_debt,p_amount,p_user);
end $$;

-- Reclamación: solo sobre lo pagado, dentro de 60 días desde el vencimiento, una abierta por deuda
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
  if current_date>coalesce(d.due_date,current_date)+60 then raise exception 'El plazo para reclamar ha vencido (60 días desde el vencimiento)'; end if;
  if exists(select 1 from plone27_disputas x where x.debt_id=p_debt and x.estado='abierta') then
    raise exception 'Ya hay una reclamación abierta para esta deuda';
  end if;
  insert into plone27_disputas(debt_id,account_id,monto_reclamado,motivo,abierta_por,plazo_resolucion)
    values(p_debt,d.account_id,p_monto,p_motivo,p_user,current_date+30) returning plone27_disputas.id into did;
  update plone27_debts set disputed=true where id=p_debt;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_user,'disputa_abierta','deuda',p_debt::text,jsonb_build_object('monto',p_monto));
  return did; end $$;

create or replace function plone27_user_disputas(p_user uuid,p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select x.id, x.debt_id, x.estado, x.monto_reclamado, x.monto_devuelto, x.motivo, x.plazo_resolucion, x.creada, x.resuelta
    from plone27_disputas x join plone27_accounts a on a.id=x.account_id
    where a.bank_id=p_bank and plone27_user_can(p_user,x.account_id,false,p_bank)) x $$;

-- Resolución por personal (aprobador). Rechazar: la deuda vuelve a cobrarse. Devolver: sale de la cuenta del acreedor.
-- Devoluciones de más de 1.000 Pz: dos personas distintas.
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
  if m>1000 then
    if x.aprobada_1 is null then
      update plone27_disputas set aprobada_1=p_actor where id=p_id;
      return jsonb_build_object('estado','pendiente_segunda_aprobacion');
    end if;
    if x.aprobada_1=p_actor then raise exception 'Otra persona debe aprobar la devolución de más de 1.000 Pz'; end if;
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

-- ---------- Bucket de logos (público para lectura; solo el servidor escribe) ----------
insert into storage.buckets(id,name,public) values('branding','branding',true) on conflict(id) do nothing;

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
