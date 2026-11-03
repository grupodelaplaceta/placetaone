-- Placeta One · 0029 · La RBU se paga a la cuenta personal principal del usuario.
-- Se eliminan las cuentas "RBU · cartera" que se abrían para cada usuario.
-- Requiere 0028. Idempotente.

-- Cuenta personal principal de un usuario en una entidad (nunca una cartera RBU)
create or replace function plone27_user_cuenta_principal(p_user uuid,p_bank uuid) returns uuid
language sql stable security definer set search_path=public as $$
  select a.id from plone27_accounts a join plone27_account_members m on m.account_id=a.id
  where m.user_id=p_user and a.bank_id=p_bank and a.kind='personal' and a.status='active'
    and m.role='holder' and a.name is distinct from 'RBU · cartera'
  order by a.created_at limit 1 $$;

-- Emisión semanal: cada bono apunta a la cuenta principal del usuario. Ya no se abren carteras.
create or replace function plone27_rbu_issue_week(p_week date,p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u record; wal uuid; bk uuid; n int:=0; amt numeric:=(plone27_setting('rbu_semanal_pz')#>>'{}')::numeric; begin
  for u in select distinct m.user_id from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where a.kind='personal' and a.status='active' and m.role='holder'
      and not exists(select 1 from plone27_customers c join plone27_junior_profiles j on j.customer_id=c.id where c.user_id=m.user_id)
  loop
    continue when exists(select 1 from plone27_rbu_bonuses where owner_user=u.user_id and week_start=p_week);
    select a.bank_id into bk from plone27_accounts a join plone27_account_members m on m.account_id=a.id
      where m.user_id=u.user_id and a.kind='personal' and a.status='active' and a.name is distinct from 'RBU · cartera'
      order by a.created_at limit 1;
    wal:=plone27_user_cuenta_principal(u.user_id,bk);
    continue when wal is null;
    insert into plone27_rbu_bonuses(owner_user,wallet_account,week_start,amount,expires_on)
      values(u.user_id,wal,p_week,amt,p_week+7);
    n:=n+1;
  end loop;
  return n; end $$;

-- Reclamación: el dinero va a la cuenta principal del usuario en la entidad del bono
create or replace function plone27_rbu_claim(p_bonus uuid,p_user uuid,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b plone27_rbu_bonuses; tx uuid; src uuid; bk uuid; dest uuid; begin
  select * into b from plone27_rbu_bonuses where id=p_bonus for update;
  if b.id is null or b.owner_user is distinct from p_user then raise exception 'Bono no encontrado'; end if;
  if b.status='claimed' then return b.claimed_tx; end if;
  if b.status<>'available' or b.expires_on<=current_date then raise exception 'Bono caducado'; end if;
  select a.bank_id into bk from plone27_accounts a where a.id=b.wallet_account;
  dest:=plone27_user_cuenta_principal(p_user,bk);
  if dest is null then raise exception 'No tienes cuenta personal en esta entidad'; end if;
  src:=plone27_rbu_source();
  if plone27_available(src)<b.amount then raise exception 'Cuenta de origen de la RBU sin fondos suficientes'; end if;
  tx:=plone27_transfer(p_key,src,dest,b.amount,'RBU semanal',p_user);
  update plone27_rbu_bonuses set status='claimed',claimed_at=now(),claimed_tx=tx,wallet_account=dest where id=p_bonus;
  return tx; end $$;

-- Paso 1 (solo lectura): qué carteras RBU existen, de quién son y cuánto saldo tienen
create or replace function plone27_rbu_carteras_resumen() returns table(cartera uuid,iban text,titular uuid,saldo_disponible numeric,bonos_pendientes int)
language sql stable security definer set search_path=public as $$
  select a.id, a.iban, a.owner_user, plone27_available(a.id),
    (select count(*)::int from plone27_rbu_bonuses b where b.wallet_account=a.id and b.status='available')
  from plone27_accounts a
  where a.name='RBU · cartera' and a.kind='personal' and a.status<>'closed'
  order by a.iban $$;

-- Paso 2: pasa los bonos pendientes y el saldo de cada cartera a la cuenta principal, y cierra la cartera.
-- Todo o nada: si una cartera no tiene cuenta principal, no se mueve ninguna.
create or replace function plone27_rbu_consolidar_carteras(p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w record; dest uuid; saldo numeric; movidas int:=0; total numeric:=0; cerradas int:=0; begin
  for w in select a.id, a.bank_id, a.owner_user, a.iban from plone27_accounts a
           where a.name='RBU · cartera' and a.kind='personal' and a.status<>'closed' order by a.id loop
    dest:=plone27_user_cuenta_principal(w.owner_user,w.bank_id);
    if dest is null then raise exception 'La cartera % no tiene cuenta principal a la que pasar el saldo', w.iban; end if;
    update plone27_rbu_bonuses set wallet_account=dest where wallet_account=w.id and status='available';
    saldo:=plone27_available(w.id);
    if saldo>0 then
      perform plone27_transfer('rbu-consolida:'||w.id::text||':'||gen_random_uuid()::text,w.id,dest,saldo,'Consolidación de cartera RBU',p_actor);
      movidas:=movidas+1; total:=total+saldo;
    end if;
    if plone27_available(w.id)<=0 then
      update plone27_accounts set status='closed' where id=w.id;
      cerradas:=cerradas+1;
    end if;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'rbu_consolidar_carteras','account',null,jsonb_build_object('carteras_con_saldo',movidas,'saldo_movido',total,'carteras_cerradas',cerradas));
  return jsonb_build_object('carteras_con_saldo',movidas,'saldo_movido',total,'carteras_cerradas',cerradas);
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
