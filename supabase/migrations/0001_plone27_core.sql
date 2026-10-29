-- Placeta One · migración inicial. Solo crea objetos plone27_*. Economía exclusiva en Pz (sin columna de divisa).
create table plone27_staff(user_id uuid primary key references auth.users on delete cascade,
  role text not null check(role in('admin','financiero','fiscal','financiacion','gestor_bancario','auditor','aprobador')),
  active boolean not null default true, created_at timestamptz default now());
create function plone27_has_role(r text[]) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from plone27_staff where user_id=auth.uid() and active and (role=any(r) or role='admin')) $$;

create table plone27_banks(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null, active boolean default true);
create table plone27_accounts(id uuid primary key default gen_random_uuid(), bank_id uuid references plone27_banks,
  kind text not null check(kind in('personal','business','shared','junior','system')), name text not null, owner_user uuid,
  status text not null default 'active' check(status in('active','blocked','closed')),
  daily_limit numeric(18,2), allow_negative boolean not null default false, created_at timestamptz default now());
create table plone27_transactions(id uuid primary key default gen_random_uuid(), kind text not null,
  status text not null default 'posted' check(status in('posted','reversed')),
  idempotency_key text unique not null, reverses uuid references plone27_transactions, memo text,
  created_by uuid, created_at timestamptz default now());
create table plone27_ledger_entries(id bigint generated always as identity primary key,
  transaction_id uuid not null references plone27_transactions, account_id uuid not null references plone27_accounts,
  direction text not null check(direction in('debit','credit')), amount numeric(18,2) not null check(amount>0), created_at timestamptz default now());
create index on plone27_ledger_entries(account_id); create index on plone27_ledger_entries(transaction_id);
create table plone27_reservations(id uuid primary key default gen_random_uuid(), account_id uuid not null references plone27_accounts,
  amount numeric(18,2) not null check(amount>0), reason text, status text default 'active' check(status in('active','released')), created_at timestamptz default now());

-- Fiscalidad interna versionada
create table plone27_tax_rules(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null);
create table plone27_tax_rule_versions(id uuid primary key default gen_random_uuid(), rule_id uuid not null references plone27_tax_rules,
  version int not null, method text not null check(method in('percent','fixed')), rate numeric(9,4) not null,
  min_amount numeric(18,2), max_amount numeric(18,2), valid_from date not null, valid_to date,
  status text not null default 'draft' check(status in('draft','published')), reason text not null,
  author uuid, approver uuid, published_at timestamptz, unique(rule_id,version));
create table plone27_tax_receipts(id uuid primary key default gen_random_uuid(), rule_version_id uuid not null references plone27_tax_rule_versions,
  account_id uuid not null references plone27_accounts, base numeric(18,2) not null, amount numeric(18,2) not null,
  status text default 'issued' check(status in('issued','paid','rectified')), due_date date, original_receipt uuid references plone27_tax_receipts, created_at timestamptz default now());

-- Subvenciones y bonos
create table plone27_grant_programs(id uuid primary key default gen_random_uuid(), name text not null, kind text check(kind in('subvencion','bono')), budget numeric(18,2) not null);
create table plone27_grants(id uuid primary key default gen_random_uuid(), program_id uuid references plone27_grant_programs,
  beneficiary_account uuid references plone27_accounts, granted numeric(18,2) not null, approved numeric(18,2) not null default 0, paid numeric(18,2) not null default 0);
create table plone27_justifications(id uuid primary key default gen_random_uuid(), grant_id uuid not null references plone27_grants,
  transaction_id uuid not null unique references plone27_transactions,   -- una transacción solo justifica una vez
  invoice_ref text unique, amount numeric(18,2) not null check(amount>0), status text default 'pending' check(status in('pending','approved','rejected')));
create table plone27_budgets(id uuid primary key default gen_random_uuid(), name text, period daterange, approved numeric(18,2), committed numeric(18,2) default 0, executed numeric(18,2) default 0, restricted boolean default false);

create table plone27_approvals(id uuid primary key default gen_random_uuid(), subject text not null, subject_id uuid, requested_by uuid, approved_by uuid, reason text not null, result text, at timestamptz default now());
create table plone27_audit_log(id bigint generated always as identity primary key, actor uuid, action text not null, entity text, entity_id text, detail jsonb, at timestamptz default now());

-- Inmutabilidad contable
create function plone27_immutable() returns trigger language plpgsql as $$ begin raise exception 'Registro contable inmutable: usa reversión'; end $$;
create trigger t_ledger_ro before update or delete on plone27_ledger_entries for each row execute function plone27_immutable();
create trigger t_tx_nodel before delete on plone27_transactions for each row execute function plone27_immutable();
create function plone27_rv_guard() returns trigger language plpgsql as $$ begin
  if old.status='published' then raise exception 'Versión publicada inmutable; crea una nueva'; end if;
  if new.status='published' and (new.approver is null or new.approver is not distinct from new.author and false) then raise exception 'Requiere aprobador'; end if;
  return new; end $$;
create trigger t_rv_guard before update on plone27_tax_rule_versions for each row execute function plone27_rv_guard();

-- Saldo derivado: créditos − débitos − reservas activas
create view plone27_account_balances with(security_invoker=true) as
select a.id account_id, a.name, a.kind, a.status,
  coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) booked,
  coalesce((select sum(r.amount) from plone27_reservations r where r.account_id=a.id and r.status='active'),0) reserved
from plone27_accounts a left join plone27_ledger_entries e on e.account_id=a.id group by a.id;

create function plone27_available(p_acc uuid) returns numeric language sql stable as
$$ select booked-reserved from plone27_account_balances where account_id=p_acc $$;

-- Contabilización atómica, idempotente y equilibrada. p_lines: [{"account":uuid,"dir":"debit|credit","amount":n}]
create function plone27_post(p_key text,p_kind text,p_memo text,p_lines jsonb,p_actor uuid,p_reverses uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare tx uuid; l record; d numeric; c numeric; net numeric; acc record;
begin
  select id into tx from plone27_transactions where idempotency_key=p_key;
  if tx is not null then return tx; end if;
  select coalesce(sum((x->>'amount')::numeric) filter(where x->>'dir'='debit'),0),
         coalesce(sum((x->>'amount')::numeric) filter(where x->>'dir'='credit'),0) into d,c from jsonb_array_elements(p_lines) x;
  if d<>c or d=0 then raise exception 'Asiento descuadrado (debe %, haber %)',d,c; end if;
  perform 1 from plone27_accounts where id in(select (x->>'account')::uuid from jsonb_array_elements(p_lines) x) order by id for update;
  for acc in select a.* from plone27_accounts a where a.id in(select (x->>'account')::uuid from jsonb_array_elements(p_lines) x) loop
    if acc.status<>'active' and p_reverses is null then raise exception 'Cuenta % no activa',acc.name; end if;
    select coalesce(sum((x->>'amount')::numeric*case x->>'dir' when 'credit' then 1 else -1 end),0) into net
      from jsonb_array_elements(p_lines) x where (x->>'account')::uuid=acc.id;
    if net<0 and not acc.allow_negative and p_reverses is null and plone27_available(acc.id)+net<0 then
      raise exception 'Saldo disponible insuficiente en %',acc.name; end if;
  end loop;
  insert into plone27_transactions(kind,idempotency_key,memo,created_by,reverses) values(p_kind,p_key,p_memo,p_actor,p_reverses) returning id into tx;
  insert into plone27_ledger_entries(transaction_id,account_id,direction,amount)
    select tx,(x->>'account')::uuid,x->>'dir',(x->>'amount')::numeric from jsonb_array_elements(p_lines) x;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'post',p_kind,tx::text,p_lines);
  return tx;
end $$;

create function plone27_transfer(p_key text,p_from uuid,p_to uuid,p_amount numeric,p_memo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$ begin
  if p_from=p_to or p_amount<=0 then raise exception 'Transferencia inválida'; end if;
  return plone27_post(p_key,'transfer',p_memo,jsonb_build_array(
    jsonb_build_object('account',p_from,'dir','debit','amount',p_amount),
    jsonb_build_object('account',p_to,'dir','credit','amount',p_amount)),p_actor);
end $$;

create function plone27_reverse(p_key text,p_tx uuid,p_reason text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$ declare r uuid; lines jsonb; begin
  if exists(select 1 from plone27_transactions where id=p_tx and status='reversed') then raise exception 'Ya revertida'; end if;
  select jsonb_agg(jsonb_build_object('account',account_id,'dir',case direction when 'debit' then 'credit' else 'debit' end,'amount',amount))
    into lines from plone27_ledger_entries where transaction_id=p_tx;
  r:=plone27_post(p_key,'reversal',p_reason,lines,p_actor,p_tx);
  update plone27_transactions set status='reversed' where id=p_tx;
  return r; end $$;

-- Cálculo fiscal (simulación pura, sin efectos)
create function plone27_tax_calc(p_version uuid,p_base numeric) returns numeric language sql stable as $$
 select round(least(coalesce(max_amount,'infinity'),greatest(coalesce(min_amount,0),
   case method when 'percent' then p_base*rate/100 else rate end)),2) from plone27_tax_rule_versions where id=p_version $$;

-- RLS: todo cerrado; solo lectura para personal. Escrituras únicamente vía funciones (service_role).
do $$ declare t text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t);
 end loop; end $$;
revoke all on function plone27_post,plone27_transfer,plone27_reverse from public,anon,authenticated;
grant execute on function plone27_post,plone27_transfer,plone27_reverse to service_role;
