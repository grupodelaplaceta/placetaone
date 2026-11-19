-- MOTOR: idempotencia estricta, titularidad, crédito interno con intereses, reservas, reversos coherentes, auditoría inmutable
alter table plone27_transactions add column req_hash text;
create or replace function plone27_post(p_key text,p_kind text,p_memo text,p_lines jsonb,p_actor uuid,p_reverses uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare tx uuid; d numeric; c numeric; net numeric; acc record; h text; old text; begin
 h:=md5(p_kind||p_lines::text);
 select id,req_hash into tx,old from plone27_transactions where idempotency_key=p_key;
 if tx is not null then
  if old is not null and old<>h then raise exception 'Idempotency-Key reutilizada con datos distintos'; end if; return tx; end if;
 select coalesce(sum((x->>'amount')::numeric) filter(where x->>'dir'='debit'),0),coalesce(sum((x->>'amount')::numeric) filter(where x->>'dir'='credit'),0) into d,c from jsonb_array_elements(p_lines) x;
 if d<>c or d=0 then raise exception 'Asiento descuadrado (debe %, haber %)',d,c; end if;
 perform 1 from plone27_accounts where id in(select (x->>'account')::uuid from jsonb_array_elements(p_lines) x) order by id for update;
 for acc in select a.* from plone27_accounts a where a.id in(select (x->>'account')::uuid from jsonb_array_elements(p_lines) x) loop
  if acc.status<>'active' and p_reverses is null then raise exception 'Cuenta % no activa',acc.name; end if;
  select coalesce(sum((x->>'amount')::numeric*case x->>'dir' when 'credit' then 1 else -1 end),0) into net from jsonb_array_elements(p_lines) x where (x->>'account')::uuid=acc.id;
  if net<0 and not acc.allow_negative and p_reverses is null and plone27_available(acc.id)+net<0 then raise exception 'Saldo disponible insuficiente en %',acc.name; end if;
 end loop;
 insert into plone27_transactions(kind,idempotency_key,memo,created_by,reverses,req_hash) values(p_kind,p_key,p_memo,p_actor,p_reverses,h) returning id into tx;
 insert into plone27_ledger_entries(transaction_id,account_id,direction,amount) select tx,(x->>'account')::uuid,x->>'dir',(x->>'amount')::numeric from jsonb_array_elements(p_lines) x;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'post',p_kind,tx::text,p_lines); return tx; end $$;

-- Titularidad: el usuario final debe ser titular/cotitular/autorizado (o tutor en Junior)
create function plone27_transfer_user(p_key text,p_user uuid,p_from uuid,p_to uuid,p_amount numeric,p_memo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$ begin
 if not exists(select 1 from plone27_account_members where account_id=p_from and user_id=p_user) and not exists(select 1 from plone27_juniors where account_id=p_from and guardian_user=p_user)
  then raise exception 'El usuario no está autorizado en la cuenta de origen'; end if;
 return plone27_transfer_fee(p_key,p_from,p_to,p_amount,p_memo,p_actor); end $$;

-- Reservas manuales (programadas, retenciones)
create function plone27_reserve(p_account uuid,p_amount numeric,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare rid uuid; begin
 perform 1 from plone27_accounts where id=p_account for update;
 if p_amount<=0 or plone27_available(p_account)<p_amount then raise exception 'Saldo disponible insuficiente'; end if;
 insert into plone27_reservations(account_id,amount,reason) values(p_account,p_amount,p_reason) returning plone27_reservations.id into rid; return rid; end $$;
create function plone27_release(p_res uuid,p_actor uuid) returns void language sql security definer set search_path=public as
$$ update plone27_reservations set status='released' where id=p_res and status='active' $$;

-- Crédito interno: descubierto con límite e intereses mensuales idempotentes
alter table plone27_accounts add column credit_limit numeric(18,2) not null default 0;
create function plone27_credit_floor() returns trigger language plpgsql security definer set search_path=public as $$
declare a plone27_accounts; k text; bal numeric; begin
 if new.direction<>'debit' then return new; end if; select * into a from plone27_accounts where id=new.account_id;
 if a.kind='system' or not a.allow_negative then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','interest') then return new; end if;
 select coalesce(sum(case when direction='credit' then amount else -amount end),0) into bal from plone27_ledger_entries where account_id=new.account_id;
 if bal-new.amount < -a.credit_limit then raise exception 'Límite de crédito superado'; end if; return new; end $$;
create trigger t_credit_floor before insert on plone27_ledger_entries for each row execute function plone27_credit_floor();
create or replace function plone27_open_account_p(p_product uuid,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare p plone27_products; k text; r jsonb; begin
 select * into p from plone27_products where id=p_product and status='active' and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
 if p.id is null then raise exception 'Producto no disponible'; end if;
 if p.kind not like 'account\_%' and p.kind<>'internal_credit' then raise exception 'No es un producto de cuenta'; end if;
 k:=case p.kind when 'account_business' then 'business' when 'account_shared' then 'shared' when 'account_junior' then 'junior' else 'personal' end;
 r:=plone27_open_account(p.bank_id,k,p_name,p_owner,p_actor);
 update plone27_accounts set product_id=p_product,daily_limit=coalesce(p.daily_limit,daily_limit),allow_negative=(p.kind='internal_credit'),credit_limit=case when p.kind='internal_credit' then coalesce(p.credit_limit,0) else 0 end where id=(r->>'id')::uuid; return r; end $$;
create function plone27_accrue_interest(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare n int:=0; a record; i numeric; begin
 for a in select ac.id,p.interest_rate r,p.fee_account fa,b.booked from plone27_accounts ac join plone27_products p on p.id=ac.product_id join plone27_account_balances b on b.account_id=ac.id
  where p.kind='internal_credit' and p.interest_rate>0 and p.fee_account is not null and ac.status='active' and b.booked<0 loop
  i:=round(-a.booked*a.r/100/12,2);
  if i>0 then begin perform plone27_post('int:'||a.id||':'||to_char(now(),'YYYY-MM'),'interest','Interés mensual',jsonb_build_array(jsonb_build_object('account',a.id,'dir','debit','amount',i),jsonb_build_object('account',a.fa,'dir','credit','amount',i)),p_actor); n:=n+1;
   exception when others then insert into plone27_incidents(kind,detail) values('interest_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end; end if; end loop; return n; end $$;

-- Reversos coherentes y recibos
create function plone27_on_reversed() returns trigger language plpgsql as $$ begin
 if new.status='reversed' and old.status<>'reversed' then
  if new.kind='reversal' then raise exception 'No se puede revertir una reversión'; end if;
  update plone27_tax_receipts r set paid_amount=greatest(r.paid_amount-d.s,0),paid_tx=null,status=case when r.paid_amount-d.s>0 then 'partial' else 'issued' end
   from (select coalesce(sum(amount),0) s from plone27_ledger_entries where transaction_id=new.id and direction='debit') d where r.paid_tx=new.id; end if; return new; end $$;
create trigger t_on_reversed before update on plone27_transactions for each row execute function plone27_on_reversed();
create function plone27_receipt_paid() returns trigger language plpgsql as $$ begin
 if new.status='paid' and new.paid_amount<new.amount then new.paid_amount:=new.amount; end if; return new; end $$;
create trigger t_receipt_paid before update on plone27_tax_receipts for each row execute function plone27_receipt_paid();
create trigger t_audit_ro before update or delete on plone27_audit_log for each row execute function plone27_immutable();

do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;
