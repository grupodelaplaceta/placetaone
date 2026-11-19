-- Placeta One · 0030 · RBU como tarjeta prepago con asignaciones semanales.
-- Una tarjeta prepago por usuario en su cuenta principal. Cada bono reclamado es una asignación con caducidad;
-- el saldo asignado queda reservado para la tarjeta. Lo no gastado al caducar vuelve a la Cuenta de Reserva.
-- Requiere 0029. Idempotente.

-- Nuevo tipo de tarjeta
alter table plone27_cards drop constraint if exists plone27_cards_kind_check,
  add constraint plone27_cards_kind_check check(kind in('digital','physical','credit','prepago')) not valid;

-- Reserva que retiene el saldo asignado a la tarjeta, y asignación de origen de cada cargo
alter table plone27_cards add column if not exists hold_reservation uuid references plone27_reservations(id);
alter table plone27_card_charges add column if not exists lote uuid;

create table if not exists plone27_rbu_lotes(
  id uuid primary key default gen_random_uuid(),
  card uuid not null references plone27_cards(id),
  bonus uuid references plone27_rbu_bonuses(id),
  amount_left numeric(18,2) not null check(amount_left>=0),
  expires_on date not null,
  creado timestamptz not null default now());
alter table plone27_card_charges drop constraint if exists plone27_card_charges_lote_fk;
alter table plone27_card_charges add constraint plone27_card_charges_lote_fk foreign key(lote) references plone27_rbu_lotes(id) not valid;

-- Tarjeta prepago RBU del usuario (en su cuenta principal). La crea si no existe.
create or replace function plone27_prepago_card(p_user uuid,p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; cid uuid; begin
  acc:=plone27_user_cuenta_principal(p_user,p_bank);
  if acc is null then raise exception 'No tienes cuenta personal en esta entidad'; end if;
  select cd.id into cid from plone27_cards cd where cd.account_id=acc and cd.kind='prepago' and cd.status<>'closed' limit 1;
  if cid is null then
    cid:=(plone27_issue_card(acc,'prepago',null,null,false,null)->>'id')::uuid;
  end if;
  return cid; end $$;

-- Retiene en la cuenta el saldo vigente de las asignaciones de la tarjeta (una sola reserva por tarjeta)
create or replace function plone27_prepago_resize_hold(p_card uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; total numeric; hid uuid; begin
  select * into c from plone27_cards where id=p_card for update;
  if c.hold_reservation is not null then
    perform plone27_release(c.hold_reservation,null);
    update plone27_cards set hold_reservation=null where id=p_card;
  end if;
  select coalesce(sum(l.amount_left),0) into total from plone27_rbu_lotes l where l.card=p_card and l.expires_on>=current_date;
  if total>0 then
    insert into plone27_reservations(account_id,amount,reason) values(c.account_id,total,'rbu hold') returning id into hid;
    update plone27_cards set hold_reservation=hid where id=p_card;
  end if;
end $$;

-- Autorización de un cargo con tarjeta prepago: consume una asignación (la de caducidad más próxima que alcance)
create or replace function plone27_prepago_authorize(p_card uuid,p_amount numeric,p_merchant uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; l plone27_rbu_lotes; res uuid; ch uuid; disponible numeric; begin
  select * into c from plone27_cards where id=p_card for update;
  if c.id is null or c.kind<>'prepago' then raise exception 'La tarjeta no es prepago'; end if;
  if c.status<>'active' then raise exception 'Tarjeta no activa'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Importe no válido'; end if;
  select coalesce(sum(x.amount_left),0) into disponible from plone27_rbu_lotes x
    where x.card=p_card and x.expires_on>=current_date;
  if disponible<p_amount then raise exception 'Saldo de la tarjeta insuficiente (disponible: %)', disponible; end if;
  select * into l from plone27_rbu_lotes x
    where x.card=p_card and x.expires_on>=current_date and x.amount_left>=p_amount
    order by x.expires_on, x.creado limit 1 for update;
  if l.id is null then raise exception 'El importe supera cada asignación de la tarjeta; divídelo en varios cargos'; end if;
  if c.hold_reservation is not null then
    perform plone27_release(c.hold_reservation,null);
    update plone27_cards set hold_reservation=null where id=p_card;
  end if;
  if plone27_available(c.account_id)<p_amount then raise exception 'Saldo insuficiente en la cuenta'; end if;
  insert into plone27_reservations(account_id,amount,reason) values(c.account_id,p_amount,'card auth') returning id into res;
  update plone27_rbu_lotes set amount_left=amount_left-p_amount where id=l.id;
  insert into plone27_card_charges(card_id,merchant_account,amount,reservation_id,lote)
    values(p_card,p_merchant,p_amount,res,l.id) returning id into ch;
  perform plone27_prepago_resize_hold(p_card);
  return ch; end $$;

-- Autorización desde la API de bancos: enruta a la tarjeta prepago o a las tarjetas de siempre
create or replace function plone27_bk_card_authorize(p_bank uuid,p_card_ref text,p_importe numeric,p_iban_comercio text,p_key text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; m uuid; ch uuid; st text; begin
  if coalesce(length(p_key),0)=0 then raise exception 'Idempotency-Key obligatoria'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'Importe no válido'; end if;
  select cd.* into c from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
    where cd.card_ref=p_card_ref and a.bank_id=p_bank;
  if c.id is null then raise exception 'Tarjeta no encontrada'; end if;
  select cg.id into ch from plone27_card_charges cg where cg.idem_key=p_key;
  if ch is not null then
    select cg.status into st from plone27_card_charges cg where cg.id=ch;
    return jsonb_build_object('cargo',ch,'estado',st);
  end if;
  select a.id into m from plone27_accounts a where a.iban=p_iban_comercio and a.status='active';
  if m is null then raise exception 'Cuenta del comercio no válida'; end if;
  if c.kind='prepago' then
    ch:=plone27_prepago_authorize(c.id,p_importe,m);
  else
    ch:=plone27_card_authorize(c.id,p_importe,m,null);
  end if;
  update plone27_card_charges set idem_key=p_key where id=ch;
  select cg.status into st from plone27_card_charges cg where cg.id=ch;
  return jsonb_build_object('cargo',ch,'estado',st); end $$;

-- Liberar un cargo devuelve su importe a la asignación; si la asignación ya caducó, el dinero vuelve a la Reserva
create or replace function plone27_bk_card_release(p_bank uuid,p_charge uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cg plone27_card_charges; cd plone27_cards; l plone27_rbu_lotes; begin
  select cg.* into cg from plone27_card_charges cg join plone27_cards cx on cx.id=cg.card_id
    join plone27_accounts a on a.id=cx.account_id
    where cg.id=p_charge and a.bank_id=p_bank for update of cg;
  if cg.id is null then raise exception 'Cargo no encontrado'; end if;
  if cg.status<>'authorized' then raise exception 'Solo se liberan cargos autorizados'; end if;
  if cg.reservation_id is not null then perform plone27_release(cg.reservation_id,null); end if;
  if cg.lote is not null then
    select * into l from plone27_rbu_lotes where id=cg.lote for update;
    if l.id is not null and l.expires_on>=current_date then
      update plone27_rbu_lotes set amount_left=amount_left+cg.amount where id=l.id;
      perform plone27_prepago_resize_hold(l.card);
    else
      select * into cd from plone27_cards where id=l.card;
      perform plone27_transfer('rbu-liberacion:'||p_charge::text,cd.account_id,plone27_rbu_source(),cg.amount,'RBU caducada (cargo liberado)',null);
    end if;
  end if;
  update plone27_card_charges set status='released' where id=p_charge;
  return jsonb_build_object('estado','released'); end $$;

-- Reclamar un bono: el dinero pasa de la Reserva a la cuenta principal, queda reservado para la tarjeta RBU
-- y se registra como asignación con la caducidad del bono.
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
  insert into plone27_rbu_lotes(card,bonus,amount_left,expires_on) values(card,p_bonus,b.amount,b.expires_on);
  perform plone27_prepago_resize_hold(card);
  if plone27_available(acc)<0 then raise exception 'Saldo insuficiente para asignar la RBU a la tarjeta'; end if;
  update plone27_rbu_bonuses set status='claimed',claimed_at=now(),claimed_tx=tx,wallet_account=acc where id=p_bonus;
  return tx; end $$;

-- Caducidad diaria: los bonos sin reclamar caducan, y lo no gastado de las asignaciones vencidas vuelve a la Reserva
create or replace function plone27_rbu_expire(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; l record; cd plone27_cards; src uuid; begin
  with x as(update plone27_rbu_bonuses set status='expired' where status='available' and expires_on<=current_date returning 1)
  select count(*) into n from x;
  src:=plone27_rbu_source();
  for l in select z.* from plone27_rbu_lotes z where z.amount_left>0 and z.expires_on<current_date loop
    select * into cd from plone27_cards where id=l.card;
    update plone27_rbu_lotes set amount_left=0 where id=l.id;
    perform plone27_prepago_resize_hold(l.card);
    perform plone27_transfer('rbu-caduca:'||l.id::text,cd.account_id,src,l.amount_left,'RBU caducada',p_actor);
  end loop;
  return n; end $$;

-- Saldo RBU del usuario por asignación y caducidad
create or replace function plone27_user_rbu_saldo(p_user uuid,p_bank uuid)
returns table(tarjeta text,importe numeric,caduca date)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select cd.card_ref, l.amount_left, l.expires_on
    from plone27_rbu_lotes l join plone27_cards cd on cd.id=l.card
    join plone27_accounts a on a.id=cd.account_id
    join plone27_account_members m on m.account_id=a.id and m.user_id=p_user
    where cd.kind='prepago' and a.bank_id=p_bank and l.amount_left>0 and l.expires_on>=current_date
    order by l.expires_on;
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
