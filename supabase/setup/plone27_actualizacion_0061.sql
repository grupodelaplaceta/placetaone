begin;
-- Placeta One · 0061 · El saldo RBU ya canjeado no caduca. Solo caducan los bonos sin canjear (3 meses).
-- El canje ingresa el saldo en la cuenta principal; la caducidad diaria ya no devuelve nada a la Reserva.
-- Requiere 0060. Idempotente. NO ejecutado en PostgreSQL.

-- Canje: el lote del saldo no caduca (fecha de referencia 2999-12-31)
create or replace function plone27_rbu_claim(p_bonus uuid,p_user uuid,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b plone27_rbu_bonuses; tx uuid; src uuid; bk uuid; acc uuid; card uuid; begin
  select * into b from plone27_rbu_bonuses where id=p_bonus for update;
  if b.id is null or b.owner_user is distinct from p_user then raise exception 'Bono no encontrado'; end if;
  if b.status='claimed' then return b.claimed_tx; end if;
  if b.status<>'available' or b.expires_on<=current_date then raise exception 'Bono caducado'; end if;
  select a.bank_id into bk from plone27_accounts a where a.id=b.wallet_account;
  acc:=plone27_user_cuenta_principal(p_user,bk);
  if acc is null then raise exception 'No tienes cuenta personal en esta entidad'; end if;
  src:=plone27_rbu_source();
  if plone27_available(src)<b.amount then raise exception 'Cuenta de origen de la RBU sin fondos suficientes'; end if;
  tx:=plone27_transfer(p_key,src,acc,b.amount,'RBU semanal',p_user);
  card:=plone27_prepago_card(p_user,bk);
  insert into plone27_rbu_lotes(card,bonus,amount_left,expires_on) values(card,p_bonus,b.amount,date '2999-12-31');
  perform plone27_prepago_resize_hold(card);
  if plone27_available(acc)<0 then raise exception 'Saldo insuficiente para asignar la RBU a la tarjeta'; end if;
  update plone27_rbu_bonuses set status='claimed',claimed_at=now(),claimed_tx=tx,wallet_account=acc where id=p_bonus;
  return tx; end $$;

-- Caducidad diaria: solo marca como caducados los bonos sin canjear. Nunca mueve saldo ya canjeado.
create or replace function plone27_rbu_expire(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_rbu_bonuses set status='expired' where status='available' and expires_on<=current_date returning 1)
  select count(*) into n from x;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'rbu_caducidad','rbu',current_date::text,jsonb_build_object('bonos_caducados',n));
  return n; end $$;

-- Saldo canjeado ya existente: se extiende y se recalcula la reserva de cada tarjeta
update plone27_rbu_lotes set expires_on=date '2999-12-31'
  where amount_left>0 and expires_on<date '2999-12-31';
do $$ declare r record; begin
  for r in select distinct card from plone27_rbu_lotes where amount_left>0 loop
    perform plone27_prepago_resize_hold(r.card);
  end loop;
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

do $$ begin raise notice 'Actualización 0061 aplicada correctamente.'; end $$;

commit;
