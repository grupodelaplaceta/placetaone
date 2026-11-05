-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0041 · Operaciones interbancarias conectadas a liquidación y tasas (tasas APAGADAS)
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0040.
-- ATENCIÓN: no se ha ejecutado en PostgreSQL. Probar en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0041 · Conexión de las operaciones interbancarias a la liquidación y a las tasas.
-- Transferencias de usuario, cargos de tarjeta hechos por el banco y cobro de deudas registran la operación
-- interbancaria. Las tasas solo se cobran si el interruptor está activo (apagado por defecto).
-- Requiere 0040. Idempotente. NO ejecutado en PostgreSQL: probar en una base de pruebas.

-- Registra la operación interbancaria y, si el interruptor está activo, cobra la tasa de la operación.
create or replace function plone27_post_movimiento(p_operacion text,p_key text,p_from uuid,p_to uuid,p_amount numeric,p_tx uuid,p_actor uuid)
returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ob uuid; db uuid; begin
  select a.bank_id into ob from plone27_accounts a where a.id=p_from;
  select a.bank_id into db from plone27_accounts a where a.id=p_to;
  if ob is null or db is null or ob=db then return; end if;
  perform plone27_registrar_op(ob,db,p_amount,p_operacion||':'||p_tx::text);
  perform plone27_cobrar_tasa(p_operacion,p_from,p_to,p_amount,p_tx::text,p_actor);
end $$;

-- Transferencia de usuario (igual que antes, más el registro y la tasa interbancaria)
create or replace function plone27_user_transfer(p_key text,p_user uuid,p_from_iban text,p_to_iban text,p_amount numeric,p_memo text,p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; t uuid; tx uuid; begin
  select id into f from plone27_accounts where iban=p_from_iban;
  if f is null or not plone27_user_can(p_user,f,true,p_bank) then raise exception 'Cuenta de origen no accesible'; end if;
  select id into t from plone27_accounts where iban=p_to_iban and status='active';
  if t is null then raise exception 'Cuenta destino no válida'; end if;
  if t=f then raise exception 'Origen y destino no pueden coincidir'; end if;
  tx:=plone27_transfer(p_key,f,t,p_amount,coalesce(p_memo,'Transferencia'),p_user);
  perform plone27_post_movimiento('transferencia_interbancaria',p_key,f,t,p_amount,tx,p_user);
  return tx;
end $$;

-- Cargo de tarjeta liquidado por el banco (igual que antes). Solo aquí se cobra la tasa de cargo de empresa:
-- la liquidación de los pagos de la pasarela ya tiene sus propias comisiones y no debe cobrar dos veces.
create or replace function plone27_bk_card_settle(p_bank uuid,p_charge uuid,p_key text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ok boolean; tx uuid; st text; org uuid; dst uuid; imp numeric; begin
  select exists(select 1 from plone27_card_charges cg join plone27_cards cd on cd.id=cg.card_id
                join plone27_accounts a on a.id=cd.account_id where cg.id=p_charge and a.bank_id=p_bank) into ok;
  if not ok then raise exception 'Cargo no encontrado'; end if;
  select cd.account_id, cg.merchant_account, cg.amount into org, dst, imp
    from plone27_card_charges cg join plone27_cards cd on cd.id=cg.card_id where cg.id=p_charge;
  tx:=plone27_card_settle(p_key,p_charge,null);
  if tx is not null then perform plone27_post_movimiento('cargo_tarjeta_empresa',p_key,org,dst,imp,tx,null); end if;
  select cg.status into st from plone27_card_charges cg where cg.id=p_charge;
  return jsonb_build_object('transaccion',tx,'estado',st);
end $$;

-- Cobro de deuda (igual que antes). Si el acreedor está en otro banco, registra la operación interbancaria. Sin tasa.
create or replace function plone27_debt_pay(p_key text,p_debt uuid,p_amount numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; tx uuid; ob uuid; db uuid; begin
  select * into d from plone27_debts where id=p_debt for update;
  if d.disputed then raise exception 'Deuda en disputa: no se cobra'; end if;
  if d.paid+p_amount>d.principal+d.authorized_charges then raise exception 'Excede la deuda'; end if;
  tx:=plone27_transfer(p_key,d.account_id,d.creditor_account,p_amount,'Deuda '||d.ref,p_actor);
  update plone27_debts set paid=paid+p_amount where id=p_debt;
  select a.bank_id into ob from plone27_accounts a where a.id=d.account_id;
  select a.bank_id into db from plone27_accounts a where a.id=d.creditor_account;
  if ob is not null and db is not null and ob<>db then perform plone27_registrar_op(ob,db,p_amount,'deuda:'||tx::text); end if;
  return tx;
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


do $$ begin raise notice 'Actualización 0041 aplicada correctamente.'; end $$;

commit;
