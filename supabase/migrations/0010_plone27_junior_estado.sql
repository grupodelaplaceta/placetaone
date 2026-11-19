-- JUNIOR: ficha de cliente con control parental heredado, aislamiento de cuentas habituales, membresía mensual; INFORMES de integridad y seguridad
create table plone27_junior_profiles(customer_id uuid primary key references plone27_customers, birth_date date not null, guardian_user uuid not null, per_tx_limit numeric(18,2), daily_limit numeric(18,2), monthly_limit numeric(18,2),
 card_enabled boolean not null default true, locked boolean not null default false);
alter table plone27_products add constraint products_junior_compat check(kind<>'account_junior' or (coalesce(credit_limit,0)=0 and interest_rate=0 and requires_guardian));
create function plone27_account_compat() returns trigger language plpgsql as $$ begin
 if new.kind='junior' and (new.allow_negative or new.credit_limit>0) then raise exception 'Una cuenta Junior no admite descubierto ni crédito'; end if; return new; end $$;
create trigger t_account_compat before insert or update on plone27_accounts for each row execute function plone27_account_compat();
create function plone27_card_compat() returns trigger language plpgsql security definer set search_path=public as $$ declare a plone27_accounts; j plone27_junior_profiles; begin
 select * into a from plone27_accounts where id=new.account_id; if a.kind<>'junior' then return new; end if;
 if new.kind='credit' then raise exception 'Una cuenta Junior no admite tarjeta de crédito'; end if;
 select * into j from plone27_junior_profiles where customer_id=a.customer_id; if j.customer_id is not null and not j.card_enabled then raise exception 'El control parental no permite tarjetas'; end if; return new; end $$;
create trigger t_card_compat before insert on plone27_cards for each row execute function plone27_card_compat();
-- Membresía mensual (renovable por la app mediante API)
create table plone27_subscriptions(id uuid primary key default gen_random_uuid(), account_id uuid unique not null references plone27_accounts, product_id uuid references plone27_products,
 status text not null default 'past_due' check(status in('active','past_due','expired','cancelled')), period_start date, period_end date not null default current_date, auto_renew boolean not null default true,
 renewals int not null default 0, last_tx uuid references plone27_transactions, created_at timestamptz default now());
create function plone27_sub_create() returns trigger language plpgsql as $$ begin
 if new.kind='junior' and new.product_id is not null and old.product_id is null then insert into plone27_subscriptions(account_id,product_id) values(new.id,new.product_id) on conflict do nothing; end if; return new; end $$;
create trigger t_sub_create after update of product_id on plone27_accounts for each row execute function plone27_sub_create();
insert into plone27_settings(key,category,description,vtype,min_v,max_v,value,sensitive,bank_overridable) values
('junior_renewal_window_days','junior','Días antes del vencimiento en que se puede renovar la membresía','number',0,31,'5',false,true),
('junior_membership_grace_days','junior','Días de gracia tras vencer antes de pasar a «expirada»','number',0,60,'5',false,true);
create function plone27_user_can(p_user uuid,p_account uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from plone27_account_members where account_id=p_account and user_id=p_user) or exists(select 1 from plone27_juniors where account_id=p_account and guardian_user=p_user)
  or exists(select 1 from plone27_accounts a join plone27_junior_profiles j on j.customer_id=a.customer_id where a.id=p_account and j.guardian_user=p_user) $$;
create function plone27_subscription_renew(p_account uuid,p_user uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare s plone27_subscriptions; p plone27_products; tx uuid; ne date; w int:=(plone27_setting('junior_renewal_window_days')#>>'{}')::int; begin
 select * into s from plone27_subscriptions where account_id=p_account for update; if s.id is null then raise exception 'La cuenta no tiene membresía'; end if;
 if s.status='cancelled' then raise exception 'Membresía cancelada'; end if;
 if p_user is not null and not plone27_user_can(p_user,p_account) then raise exception 'El usuario no está autorizado en la cuenta'; end if;
 if s.status='active' and s.period_end>current_date+w then raise exception 'Membresía vigente hasta % (renovable en los últimos % días)',s.period_end,w; end if;
 select * into p from plone27_products where id=s.product_id; ne:=(greatest(s.period_end,current_date)+interval '1 month')::date;
 if p.monthly_fee>0 then
  begin tx:=plone27_post('sub:'||p_account||':'||s.period_end,'membership','Membresía Junior',jsonb_build_array(jsonb_build_object('account',p_account,'dir','debit','amount',p.monthly_fee),jsonb_build_object('account',p.fee_account,'dir','credit','amount',p.monthly_fee)),p_actor);
  exception when others then update plone27_subscriptions set status='past_due' where id=s.id; return jsonb_build_object('renewed',false,'reason',sqlerrm); end; end if;
 update plone27_subscriptions set status='active',period_start=greatest(s.period_end,current_date),period_end=ne,renewals=renewals+1,last_tx=tx where id=s.id;
 return jsonb_build_object('renewed',true,'period_end',ne,'transaction',tx); end $$;
create function plone27_subscriptions_sweep(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare s record; r jsonb; ren int:=0; exp int:=0; g int:=(plone27_setting('junior_membership_grace_days')#>>'{}')::int; begin
 for s in select * from plone27_subscriptions where status in('active','past_due') and period_end<=current_date loop
  if s.auto_renew then r:=plone27_subscription_renew(s.account_id,null,p_actor); if (r->>'renewed')='true' then ren:=ren+1; continue; end if; end if;
  if s.period_end+g<current_date then update plone27_subscriptions set status='expired' where id=s.id; exp:=exp+1; else update plone27_subscriptions set status='past_due' where id=s.id and status='active'; end if; end loop;
 return jsonb_build_object('renewed',ren,'expired',exp); end $$;
-- Reglas Junior en el libro: control parental heredado de la ficha + membresía vigente + sin cuentas habituales
create function plone27_junior_profile() returns trigger language plpgsql security definer set search_path=public as $$
declare a plone27_accounts; j plone27_junior_profiles; k text; s plone27_subscriptions; ud numeric; um numeric; begin
 if new.direction<>'debit' then return new; end if; select * into a from plone27_accounts where id=new.account_id; if a.kind<>'junior' then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','membership') then return new; end if;
 select * into s from plone27_subscriptions where account_id=a.id; if s.id is not null and s.status<>'active' then raise exception 'Membresía Junior no vigente: renuévala para operar'; end if;
 select * into j from plone27_junior_profiles where customer_id=a.customer_id; if j.customer_id is null then return new; end if;
 if j.locked then raise exception 'Control parental: cuenta bloqueada por el tutor'; end if;
 if j.per_tx_limit is not null and new.amount>j.per_tx_limit then raise exception 'Control parental: supera el límite por operación (% Pz)',j.per_tx_limit; end if;
 select coalesce(sum(e.amount) filter(where e.created_at::date=current_date),0),coalesce(sum(e.amount) filter(where e.created_at>=date_trunc('month',now())),0) into ud,um
  from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.account_id=a.id and e.direction='debit' and t.kind not in('reversal','membership');
 if j.daily_limit is not null and ud+new.amount>j.daily_limit then raise exception 'Control parental: supera el límite diario (% Pz)',j.daily_limit; end if;
 if j.monthly_limit is not null and um+new.amount>j.monthly_limit then raise exception 'Control parental: supera el límite mensual (% Pz)',j.monthly_limit; end if; return new; end $$;
create trigger t_junior_profile before insert on plone27_ledger_entries for each row execute function plone27_junior_profile();
create function plone27_junior_counterparty() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if exists(select 1 from (select distinct n.transaction_id from new_rows n join plone27_transactions t on t.id=n.transaction_id where t.kind<>'reversal') x
  where exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind='junior')
   and exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind in('personal','shared','business')))
 then raise exception 'Cuenta Junior: no puede enviar ni recibir de cuentas de clientes habituales'; end if; return null; end $$;
create trigger t_junior_cp after insert on plone27_ledger_entries referencing new table as new_rows for each statement execute function plone27_junior_counterparty();
create or replace function plone27_ledger_limits() returns trigger language plpgsql security definer set search_path=public as $$
declare a plone27_accounts; k text; j plone27_juniors; used numeric; dl numeric; jl numeric; begin
 if new.direction<>'debit' then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','tax_refund','membership') then return new; end if;
 select * into a from plone27_accounts where id=new.account_id;
 dl:=coalesce(a.daily_limit,nullif((plone27_setting('default_daily_limit',a.bank_id)#>>'{}')::numeric,0));
 if dl is not null then select coalesce(sum(e.amount),0) into used from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.account_id=new.account_id and e.direction='debit' and t.kind<>'reversal' and e.created_at::date=current_date;
  if used+new.amount>dl then raise exception 'Límite diario superado (% Pz)',dl; end if; end if;
 if a.kind='junior' then select * into j from plone27_juniors where account_id=a.id; jl:=coalesce(j.per_tx_limit,(plone27_setting('junior_default_limit',a.bank_id)#>>'{}')::numeric);
  if new.amount>jl then raise exception 'Junior: supera el límite por operación; requiere tutor'; end if; end if; return new; end $$;
-- INFORMES: integridad y seguridad (los consume el panel de estado)
create function plone27_integrity_report() returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('check',c,'severity',sv,'count',n,'detail',dt)),'[]'::jsonb) from (
  select 'Asientos descuadrados' c,'critical' sv,count(*) n,'Operaciones donde débitos y créditos no coinciden' dt from (select transaction_id from plone27_ledger_entries group by 1 having sum(case when direction='debit' then amount else -amount end)<>0) x
  union all select 'Saldo negativo sin descubierto autorizado','critical',count(*),'Cuentas (no sistema) con saldo < 0 y sin crédito' from plone27_account_balances b join plone27_accounts a on a.id=b.account_id where b.booked<0 and a.kind<>'system' and not a.allow_negative
  union all select 'Descubierto sobre el límite de crédito','critical',count(*),'Cuentas con crédito que exceden su límite' from plone27_account_balances b join plone27_accounts a on a.id=b.account_id where a.allow_negative and a.kind<>'system' and b.booked< -a.credit_limit
  union all select 'Mezcla Junior / cuentas habituales','critical',count(*),'Operaciones entre una cuenta Junior y una cuenta de cliente habitual' from (select e.transaction_id from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id join plone27_transactions t on t.id=e.transaction_id where t.kind<>'reversal' group by 1 having bool_or(a.kind='junior') and bool_or(a.kind in('personal','shared','business'))) y
  union all select 'Cuentas Junior con crédito o descubierto','critical',count(*),'No compatible con Junior' from plone27_accounts where kind='junior' and (allow_negative or credit_limit>0)
  union all select 'Cuentas Junior sin ficha de cliente','warning',count(*),'Sin control parental heredado' from plone27_accounts a where a.kind='junior' and not exists(select 1 from plone27_junior_profiles j where j.customer_id=a.customer_id) and not exists(select 1 from plone27_juniors j2 where j2.account_id=a.id)
  union all select 'Membresías Junior vencidas','warning',count(*),'Pendientes de renovar o expiradas' from plone27_subscriptions where status in('past_due','expired')
  union all select 'Recibos pagados sin transacción','warning',count(*),'Estado pagado sin cobro contabilizado' from plone27_tax_receipts where status='paid' and paid_tx is null
  union all select 'Cuentas activas en entidad no activa','warning',count(*),'Entidad suspendida o cerrada con cuentas activas' from plone27_accounts a join plone27_banks b on b.id=a.bank_id where a.status='active' and b.status in('suspended','closed')
  union all select 'Productos activos sin aprobación','critical',count(*),'' from plone27_products where status='active' and approved_by is null
  union all select 'Conflictos de normas sin resolver','warning',count(*),'' from plone27_incidents where kind='policy_conflict' and status='open'
  union all select 'Disputas fuera de plazo','warning',count(*),'' from plone27_disputes where status='open' and due_at<now()
  union all select 'Reservas activas de más de 30 días','info',count(*),'' from plone27_reservations where status='active' and created_at<now()-interval '30 days'
  union all select 'Eventos de webhook fallidos','warning',count(*),'' from plone27_outbox where status='failed') q $$;
create function plone27_security_report() returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('check',c,'severity',sv,'count',n,'detail',dt)),'[]'::jsonb) from (
  select 'Tablas sin RLS' c,'critical' sv,count(*) n,'Tablas plone27_* con seguridad por filas desactivada' dt from pg_class c join pg_namespace s on s.oid=c.relnamespace where s.nspname='public' and c.relkind='r' and c.relname like 'plone27\_%' and not c.relrowsecurity
  union all select 'Políticas que permiten escribir','critical',count(*),'Las escrituras solo deben pasar por el servidor' from pg_policies where schemaname='public' and tablename like 'plone27\_%' and cmd<>'SELECT'
  union all select 'Funciones ejecutables por anon/authenticated','critical',count(*),'Solo service_role debe ejecutarlas' from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))
  union all select 'Webhooks sin https','critical',count(*),'' from plone27_webhooks where url !~ '^https://'
  union all select 'Claves de API sin permisos','warning',count(*),'' from plone27_api_clients where active and cardinality(scopes)=0
  union all select 'Sin administradores activos','critical',case when count(*)=0 then 1 else 0 end,'' from plone27_staff where role='admin' and active
  union all select 'Más de 3 administradores activos','warning',case when count(*)>3 then count(*) else 0 end,'Principio de mínimo privilegio' from plone27_staff where role='admin' and active
  union all select 'Cambios sensibles pendientes de aprobar','info',count(*),'' from plone27_setting_changes where status='pending') q $$;
do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;
