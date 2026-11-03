-- Titulares y permisos por cuenta, Junior, límites diarios (aplicados en el libro, no eludibles)
create table plone27_account_members(account_id uuid references plone27_accounts, user_id uuid, role text not null check(role in('holder','coholder','authorized')), primary key(account_id,user_id));
create table plone27_juniors(account_id uuid primary key references plone27_accounts, birth_date date not null, guardian_user uuid not null, per_tx_limit numeric(18,2) not null);
create function plone27_ledger_limits() returns trigger language plpgsql security definer set search_path=public as $$
declare a plone27_accounts; k text; j plone27_juniors; used numeric; begin
 if new.direction<>'debit' then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','tax_refund') then return new; end if;
 select * into a from plone27_accounts where id=new.account_id;
 if a.daily_limit is not null then
  select coalesce(sum(e.amount),0) into used from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
   where e.account_id=new.account_id and e.direction='debit' and t.kind<>'reversal' and e.created_at::date=current_date;
  if used+new.amount>a.daily_limit then raise exception 'Límite diario superado (% Pz)',a.daily_limit; end if; end if;
 if a.kind='junior' then select * into j from plone27_juniors where account_id=a.id;
  if j.account_id is null or new.amount>j.per_tx_limit then raise exception 'Junior: supera el límite por operación; requiere tutor'; end if; end if;
 return new; end $$;
create trigger t_limits before insert on plone27_ledger_entries for each row execute function plone27_ledger_limits();
create function plone27_staff_set(p_user uuid,p_role text,p_active boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 insert into plone27_staff(user_id,role,active) values(p_user,p_role,p_active) on conflict(user_id) do update set role=p_role,active=p_active;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'staff_set','staff',p_user::text,jsonb_build_object('role',p_role,'active',p_active)); end $$;

-- Lotes y nóminas (cada elemento idempotente y aislado: uno fallido no bloquea el resto)
create table plone27_batches(id uuid primary key default gen_random_uuid(), kind text not null check(kind in('payroll','batch')), from_account uuid not null references plone27_accounts, status text not null default 'open' check(status in('open','done','partial')));
create table plone27_batch_items(id uuid primary key default gen_random_uuid(), batch_id uuid not null references plone27_batches, to_account uuid not null references plone27_accounts,
 amount numeric(18,2) not null check(amount>0), status text not null default 'pending' check(status in('pending','paid','failed')), error text);
create function plone27_run_batch(p_batch uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare b plone27_batches; i record; ok int:=0; ko int:=0; begin
 select * into b from plone27_batches where id=p_batch for update;
 for i in select * from plone27_batch_items where batch_id=p_batch and status in('pending','failed') order by id loop
  begin perform plone27_transfer_fee('batch:'||i.id,b.from_account,i.to_account,i.amount,b.kind,p_actor); update plone27_batch_items set status='paid',error=null where id=i.id; ok:=ok+1;
  exception when others then update plone27_batch_items set status='failed',error=sqlerrm where id=i.id; ko:=ko+1; end; end loop;
 update plone27_batches set status=case when ko=0 then 'done' else 'partial' end where id=p_batch; return jsonb_build_object('paid',ok,'failed',ko); end $$;

-- Facturas internas, liquidación bancaria y conciliación fiscal
create table plone27_invoices(id uuid primary key default gen_random_uuid(), ref text unique, account_id uuid references plone27_accounts, concept text, amount numeric(18,2) not null check(amount>0), status text default 'issued' check(status in('issued','paid','void')));
create table plone27_settlements(id uuid primary key default gen_random_uuid(), ref text unique, bank_id uuid not null references plone27_banks, period_from date not null, period_to date not null,
 evaluated numeric(18,2), collected numeric(18,2), pending numeric(18,2), refunded numeric(18,2), unique(bank_id,period_from,period_to));
create trigger t_ref before insert on plone27_invoices for each row execute function plone27_set_ref('FAC');
create trigger t_ref before insert on plone27_settlements for each row execute function plone27_set_ref('LIQ');
create function plone27_settle_bank(p_bank uuid,p_from date,p_to date,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare sid uuid; begin
 select id into sid from plone27_settlements where bank_id=p_bank and period_from=p_from and period_to=p_to; if sid is not null then return sid; end if;
 insert into plone27_settlements(bank_id,period_from,period_to,evaluated,collected,pending,refunded)
  select p_bank,p_from,p_to,coalesce(sum(r.amount),0),coalesce(sum(r.amount) filter(where r.status='paid'),0),coalesce(sum(r.amount) filter(where r.status='issued'),0),coalesce(sum(r.refunded),0)
  from plone27_tax_receipts r join plone27_accounts a on a.id=r.account_id where a.bank_id=p_bank and r.created_at::date between p_from and p_to returning plone27_settlements.id into sid; return sid; end $$;

-- Deuda con origen autorizado
alter table plone27_debts add column creditor_account uuid references plone27_accounts;
create function plone27_debt_pay(p_key text,p_debt uuid,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare d plone27_debts; tx uuid; begin
 select * into d from plone27_debts where id=p_debt for update; if d.disputed then raise exception 'Deuda en disputa: no se cobra'; end if;
 if d.paid+p_amount>d.principal+d.authorized_charges then raise exception 'Excede la deuda'; end if;
 tx:=plone27_transfer(p_key,d.account_id,d.creditor_account,p_amount,'Deuda '||d.ref,p_actor); update plone27_debts set paid=paid+p_amount where id=p_debt; return tx; end $$;

-- Tarjetas físicas: pedido → producción → envío → activación (suspendida hasta activar)
create table plone27_card_orders(id uuid primary key default gen_random_uuid(), card_id uuid not null unique references plone27_cards, status text not null default 'ordered' check(status in('ordered','produced','shipped','activated','cancelled')), updated_at timestamptz default now());
create function plone27_card_order_step(p_card uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare o text; begin
 if p_to='ordered' then insert into plone27_card_orders(card_id) values(p_card); update plone27_cards set status='suspended' where id=p_card; return; end if;
 select status into o from plone27_card_orders where card_id=p_card for update;
 if (o,p_to) not in(('ordered','produced'),('produced','shipped'),('shipped','activated'),('ordered','cancelled'),('produced','cancelled')) then raise exception 'Transición de pedido no permitida'; end if;
 update plone27_card_orders set status=p_to,updated_at=now() where card_id=p_card; if p_to='activated' then update plone27_cards set status='active' where id=p_card; end if; end $$;

-- Previsión de caja
create function plone27_cash_forecast(p_days int,p_actor uuid) returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('horizon_days',p_days,
  'scheduled_out',coalesce((select sum(amount) from plone27_scheduled where status='active' and run_at<=now()+make_interval(days=>p_days)),0),
  'tax_due',coalesce((select sum(amount) from plone27_tax_receipts where status='issued' and due_date<=current_date+p_days),0),
  'grants_pending',coalesce((select sum(amount) from plone27_justifications where status='approved'),0)) $$;

do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t<>'plone27_api_clients' and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname<>'plone27_has_role' loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;
