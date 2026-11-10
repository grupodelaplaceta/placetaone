-- Antes de crear nada: borra TODAS las variantes existentes de las funciones que cambian de firma
-- (argumentos o tipo devuelto), sea cual sea la versión que tenga la base. Evita 42P13 y 'cannot change return type'.
do $$ declare r record; begin
  for r in select p.oid::regprocedure::text as f from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname = any(array['plone27_checkout_create','plone27_session_check','plone27_user_accounts','plone27_user_can','plone27_user_receipts','plone27_user_transactions','plone27_user_transfer']) loop
    execute 'drop function if exists '||r.f||' cascade';
  end loop;
end $$;

-- =====================================================================================================
-- PLACETA ONE · INSTALACIÓN COMPLETA DE LA BASE DE DATOS (un solo archivo)
-- Grupo de La Placeta · Plan 2027
--
-- QUÉ HACE
--   Crea lo que no existe, modifica lo que ya existe y deja la base lista para todo el sistema.
--   Equivale a ejecutar, en orden, las migraciones 0001–0013 y los datos de la norma (seeds 0011–0013),
--   con cada sentencia escrita para poder repetirse sin error. Ejecutarlo dos veces no duplica nada.
--
-- REQUISITOS
--   · PostgreSQL 15 o superior con el esquema auth (proyecto Supabase). Usa gen_random_uuid() y sha256().
--   · Ejecutarlo como propietario de la base (rol postgres en Supabase). Todo va en una transacción:
--     si algo falla, no queda nada a medias.
--
-- LO QUE NO PUEDE HACER (requiere personas, no SQL)
--   · Crear usuarios de acceso: el primer administrador se da de alta después, vinculando un usuario de Auth.
--   · Aprobar la norma: las versiones de tributos entran en BORRADOR; las publica un aprobador distinto del autor.
--   · Aprobar Capitalia: la entidad se crea en borrador; hay que activarla y abrir su cuenta principal.
--   · Registrar aprobadores de las cuentas institucionales.
--   · Variables de entorno en Vercel (CRON_SECRET, claves de Supabase).
-- La vista plone27_listo (al final de este archivo) lista cada uno de estos pasos con su estado.
--
-- AVISO SOBRE REEJECUCIÓN
--   Los ajustes de la norma (SMI, demora desactivada, Capitalia como pagador) se vuelven a fijar en cada
--   ejecución. Si después has cambiado uno de ellos desde el panel, vuelve a ejecutar este archivo lo
--   restablecerá. Para cambios posteriores a la instalación, usa el panel, no este archivo.
-- =====================================================================================================

begin;

-- ==================== MIGRACIÓN (0001_plone27_core.sql) ====================
-- Placeta One · migración inicial. Solo crea objetos plone27_*. Economía exclusiva en Pz (sin columna de divisa).
create table if not exists plone27_staff(user_id uuid primary key references auth.users on delete cascade,
  role text not null check(role in('admin','financiero','fiscal','financiacion','gestor_bancario','auditor','aprobador')),
  active boolean not null default true, created_at timestamptz default now());
create or replace function plone27_has_role(r text[]) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from plone27_staff where user_id=auth.uid() and active and (role=any(r) or role='admin')) $$;

create table if not exists plone27_banks(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null, active boolean default true);
create table if not exists plone27_accounts(id uuid primary key default gen_random_uuid(), bank_id uuid references plone27_banks,
  kind text not null check(kind in('personal','business','shared','junior','system')), name text not null, owner_user uuid,
  status text not null default 'active' check(status in('active','blocked','closed')),
  daily_limit numeric(18,2), allow_negative boolean not null default false, created_at timestamptz default now());
create table if not exists plone27_transactions(id uuid primary key default gen_random_uuid(), kind text not null,
  status text not null default 'posted' check(status in('posted','reversed')),
  idempotency_key text unique not null, reverses uuid references plone27_transactions, memo text,
  created_by uuid, created_at timestamptz default now());
create table if not exists plone27_ledger_entries(id bigint generated always as identity primary key,
  transaction_id uuid not null references plone27_transactions, account_id uuid not null references plone27_accounts,
  direction text not null check(direction in('debit','credit')), amount numeric(18,2) not null check(amount>0), created_at timestamptz default now());
create index if not exists plone27_ledger_entries_account_id_idx on plone27_ledger_entries(account_id); create index if not exists plone27_ledger_entries_transaction_id_idx on plone27_ledger_entries(transaction_id);
create table if not exists plone27_reservations(id uuid primary key default gen_random_uuid(), account_id uuid not null references plone27_accounts,
  amount numeric(18,2) not null check(amount>0), reason text, status text default 'active' check(status in('active','released')), created_at timestamptz default now());

-- Fiscalidad interna versionada
create table if not exists plone27_tax_rules(id uuid primary key default gen_random_uuid(), code text unique not null, name text not null);
create table if not exists plone27_tax_rule_versions(id uuid primary key default gen_random_uuid(), rule_id uuid not null references plone27_tax_rules,
  version int not null, method text not null check(method in('percent','fixed')), rate numeric(9,4) not null,
  min_amount numeric(18,2), max_amount numeric(18,2), valid_from date not null, valid_to date,
  status text not null default 'draft' check(status in('draft','published')), reason text not null,
  author uuid, approver uuid, published_at timestamptz, unique(rule_id,version));
create table if not exists plone27_tax_receipts(id uuid primary key default gen_random_uuid(), rule_version_id uuid not null references plone27_tax_rule_versions,
  account_id uuid not null references plone27_accounts, base numeric(18,2) not null, amount numeric(18,2) not null,
  status text default 'issued' check(status in('issued','paid','rectified')), due_date date, original_receipt uuid references plone27_tax_receipts, created_at timestamptz default now());

-- Subvenciones y bonos
create table if not exists plone27_grant_programs(id uuid primary key default gen_random_uuid(), name text not null, kind text check(kind in('subvencion','bono')), budget numeric(18,2) not null);
create table if not exists plone27_grants(id uuid primary key default gen_random_uuid(), program_id uuid references plone27_grant_programs,
  beneficiary_account uuid references plone27_accounts, granted numeric(18,2) not null, approved numeric(18,2) not null default 0, paid numeric(18,2) not null default 0);
create table if not exists plone27_justifications(id uuid primary key default gen_random_uuid(), grant_id uuid not null references plone27_grants,
  transaction_id uuid not null unique references plone27_transactions,   -- una transacción solo justifica una vez
  invoice_ref text unique, amount numeric(18,2) not null check(amount>0), status text default 'pending' check(status in('pending','approved','rejected')));
create table if not exists plone27_budgets(id uuid primary key default gen_random_uuid(), name text, period daterange, approved numeric(18,2), committed numeric(18,2) default 0, executed numeric(18,2) default 0, restricted boolean default false);

create table if not exists plone27_approvals(id uuid primary key default gen_random_uuid(), subject text not null, subject_id uuid, requested_by uuid, approved_by uuid, reason text not null, result text, at timestamptz default now());
create table if not exists plone27_audit_log(id bigint generated always as identity primary key, actor uuid, action text not null, entity text, entity_id text, detail jsonb, at timestamptz default now());

-- Inmutabilidad contable
create or replace function plone27_immutable() returns trigger language plpgsql as $$ begin raise exception 'Registro contable inmutable: usa reversión'; end $$;
drop trigger if exists t_ledger_ro on plone27_ledger_entries;
create trigger t_ledger_ro before update or delete on plone27_ledger_entries for each row execute function plone27_immutable();
drop trigger if exists t_tx_nodel on plone27_transactions;
create trigger t_tx_nodel before delete on plone27_transactions for each row execute function plone27_immutable();
create or replace function plone27_rv_guard() returns trigger language plpgsql as $$
#variable_conflict use_column begin
  if old.status='published' then raise exception 'Versión publicada inmutable; crea una nueva'; end if;
  if new.status='published' and (new.approver is null or new.approver is not distinct from new.author and false) then raise exception 'Requiere aprobador'; end if;
  return new; end $$;
drop trigger if exists t_rv_guard on plone27_tax_rule_versions;
create trigger t_rv_guard before update on plone27_tax_rule_versions for each row execute function plone27_rv_guard();

-- Saldo derivado: créditos − débitos − reservas activas
drop view if exists plone27_account_balances cascade;
create view plone27_account_balances with(security_invoker=true) as
select a.id account_id, a.name, a.kind, a.status,
  coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) booked,
  coalesce((select sum(r.amount) from plone27_reservations r where r.account_id=a.id and r.status='active'),0) reserved
from plone27_accounts a left join plone27_ledger_entries e on e.account_id=a.id group by a.id;

create or replace function plone27_available(p_acc uuid) returns numeric language sql stable as
$$ select booked-reserved from plone27_account_balances where account_id=p_acc $$;

-- Contabilización atómica, idempotente y equilibrada. p_lines: [{"account":uuid,"dir":"debit|credit","amount":n}]
create or replace function plone27_post(p_key text,p_kind text,p_memo text,p_lines jsonb,p_actor uuid,p_reverses uuid default null)
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

create or replace function plone27_transfer(p_key text,p_from uuid,p_to uuid,p_amount numeric,p_memo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if p_from=p_to or p_amount<=0 then raise exception 'Transferencia inválida'; end if;
  return plone27_post(p_key,'transfer',p_memo,jsonb_build_array(
    jsonb_build_object('account',p_from,'dir','debit','amount',p_amount),
    jsonb_build_object('account',p_to,'dir','credit','amount',p_amount)),p_actor);
end $$;

create or replace function plone27_reverse(p_key text,p_tx uuid,p_reason text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare r uuid; lines jsonb; begin
  if exists(select 1 from plone27_transactions where id=p_tx and status='reversed') then raise exception 'Ya revertida'; end if;
  select jsonb_agg(jsonb_build_object('account',account_id,'dir',case direction when 'debit' then 'credit' else 'debit' end,'amount',amount))
    into lines from plone27_ledger_entries where transaction_id=p_tx;
  r:=plone27_post(p_key,'reversal',p_reason,lines,p_actor,p_tx);
  update plone27_transactions set status='reversed' where id=p_tx;
  return r; end $$;

-- Cálculo fiscal (simulación pura, sin efectos)
create or replace function plone27_tax_calc(p_version uuid,p_base numeric) returns numeric language sql stable as $$
 select round(least(coalesce(max_amount,'infinity'),greatest(coalesce(min_amount,0),
   case method when 'percent' then p_base*rate/100 else rate end)),2) from plone27_tax_rule_versions where id=p_version $$;

-- RLS: todo cerrado; solo lectura para personal. Escrituras únicamente vía funciones (service_role).
do $$ declare t text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
 end loop; end $$;
revoke all on function plone27_post,plone27_transfer,plone27_reverse from public,anon,authenticated;
grant execute on function plone27_post,plone27_transfer,plone27_reverse to service_role;

-- ==================== MIGRACIÓN (0002_plone27_fases.sql) ====================
-- Placeta One v1.1 · bancos, tarifas, vías fiscales, tarjetas, financiación. Solo Pz.
-- BANCOS: ciclo de vida
alter table plone27_banks add column if not exists description text, add column if not exists status text not null default 'draft' check(status in('draft','review','active','suspended','closed')),
 add column if not exists valid_from date, add column if not exists valid_to date, add column if not exists approved_by uuid, add column if not exists config jsonb not null default '{}';
create or replace function plone27_bank_guard() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if new.status is distinct from old.status then
  if (old.status,new.status) not in(('draft','review'),('review','draft'),('review','active'),('active','suspended'),('suspended','active'),('active','closed'),('suspended','closed'))
   then raise exception 'Transición % → % no permitida',old.status,new.status; end if;
  if new.status='active' and new.approved_by is null then raise exception 'Activar requiere aprobación registrada'; end if; end if; return new; end $$;
drop trigger if exists t_bank_guard on plone27_banks;
create trigger t_bank_guard before update on plone27_banks for each row execute function plone27_bank_guard();
create table if not exists plone27_incidents(id uuid primary key default gen_random_uuid(), kind text, detail jsonb, status text default 'open', at timestamptz default now());

-- TARIFAS (distintas de impuestos)
create table if not exists plone27_fee_rules(id uuid primary key default gen_random_uuid(), bank_id uuid references plone27_banks, op_type text not null default 'transfer',
 method text not null check(method in('percent','fixed')), rate numeric(9,4) not null, min_amount numeric(18,2), max_amount numeric(18,2),
 payer text not null check(payer in('user','bank','both','exempt')), bank_pay_account uuid references plone27_accounts,
 beneficiary_account uuid not null references plone27_accounts, valid_from date not null, valid_to date, approved_by uuid);
create or replace function plone27_transfer_fee(p_key text,p_from uuid,p_to uuid,p_amount numeric,p_memo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b uuid; r plone27_fee_rules; fee numeric:=0; u numeric:=0; lines jsonb; begin
 select bank_id into b from plone27_accounts where id=p_from;
 if b is not null and not exists(select 1 from plone27_banks where id=b and status='active') then raise exception 'Banco no activo para nuevas operaciones'; end if;
 lines:=jsonb_build_array(jsonb_build_object('account',p_from,'dir','debit','amount',p_amount),jsonb_build_object('account',p_to,'dir','credit','amount',p_amount));
 select * into r from plone27_fee_rules where bank_id=b and op_type='transfer' and approved_by is not null and current_date>=valid_from and (valid_to is null or current_date<=valid_to) order by valid_from desc limit 1;
 if found and r.payer<>'exempt' then
  fee:=round(least(coalesce(r.max_amount,'infinity'),greatest(coalesce(r.min_amount,0),case r.method when 'percent' then p_amount*r.rate/100 else r.rate end)),2);
  u:=case r.payer when 'user' then fee when 'both' then round(fee/2,2) else 0 end;
  if u>0 then lines:=lines||jsonb_build_object('account',p_from,'dir','debit','amount',u); end if;
  if fee-u>0 then lines:=lines||jsonb_build_object('account',r.bank_pay_account,'dir','debit','amount',fee-u); end if;
  if fee>0 then lines:=lines||jsonb_build_object('account',r.beneficiary_account,'dir','credit','amount',fee); end if;
 end if;
 return plone27_post(p_key,'transfer',p_memo,lines,p_actor); end $$;

-- FISCALIDAD: jerarquía, vías, exenciones, evaluaciones
alter table plone27_tax_rules add column if not exists max_rate numeric(9,4), add column if not exists collector_account uuid references plone27_accounts;
alter table plone27_tax_rule_versions add column if not exists scope_bank uuid references plone27_banks, add column if not exists scope_op text,
 add column if not exists retro_mode text not null default 'prohibited' check(retro_mode in('prohibited','simulation','automatic'));
create or replace function plone27_rv_cap() returns trigger language plpgsql as $$
#variable_conflict use_column declare m numeric; begin
 select max_rate into m from plone27_tax_rules where id=new.rule_id;
 if (new.scope_bank is not null or new.scope_op is not null) and m is not null and new.method='percent' and new.rate>m then raise exception 'Regla específica supera el límite central (%)',m; end if; return new; end $$;
drop trigger if exists t_rv_cap on plone27_tax_rule_versions;
create trigger t_rv_cap before insert or update on plone27_tax_rule_versions for each row execute function plone27_rv_cap();
create table if not exists plone27_tax_exemptions(id uuid primary key default gen_random_uuid(), rule_id uuid references plone27_tax_rules, account_id uuid references plone27_accounts,
 valid_from date not null, valid_to date, reason text not null, legal_basis text not null, approved_by uuid not null);
create table if not exists plone27_tax_distribution(id uuid primary key default gen_random_uuid(), rule_id uuid not null references plone27_tax_rules, account_id uuid not null references plone27_accounts,
 pct numeric(5,2) not null check(pct>0 and pct<=100), approved_by uuid);
create or replace function plone27_dist_guard() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if (select coalesce(sum(pct),0) from plone27_tax_distribution where rule_id=new.rule_id and id<>new.id)+new.pct>100 then raise exception 'La distribución supera el 100%%'; end if; return new; end $$;
drop trigger if exists t_dist on plone27_tax_distribution;
create trigger t_dist before insert or update on plone27_tax_distribution for each row execute function plone27_dist_guard();
create table if not exists plone27_tax_evaluations(id uuid primary key default gen_random_uuid(), event_key text unique not null, rule_id uuid references plone27_tax_rules,
 rule_version_id uuid references plone27_tax_rule_versions, account_id uuid references plone27_accounts,
 pathway text not null check(pathway in('automatica','periodica','recibo','declaracion','regularizacion','liquidacion_bancaria','devolucion','revision_manual')),
 base numeric(18,2), amount numeric(18,2), status text not null default 'calculated' check(status in('calculated','review','exempt')), created_at timestamptz default now());
alter table plone27_tax_receipts add column if not exists evaluation_id uuid references plone27_tax_evaluations, add column if not exists paid_tx uuid references plone27_transactions, add column if not exists refunded numeric(18,2) not null default 0;

create or replace function plone27_tax_issue(p_code text,p_account uuid,p_base numeric,p_event_key text,p_op text,p_pathway text,p_due date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ev uuid; rid uuid; ids uuid[]; v uuid; amt numeric; b uuid; begin
 select id into ev from plone27_tax_evaluations where event_key=p_event_key;
 if ev is not null then return (select id from plone27_tax_receipts where evaluation_id=ev); end if;
 select id into rid from plone27_tax_rules where code=p_code; select bank_id into b from plone27_accounts where id=p_account;
 with c as(select v.id,(v.scope_bank is not null)::int*2+(v.scope_op is not null)::int s from plone27_tax_rule_versions v where v.rule_id=rid and v.status='published'
   and current_date>=v.valid_from and (v.valid_to is null or current_date<=v.valid_to) and (v.scope_bank is null or v.scope_bank=b) and (v.scope_op is null or v.scope_op=p_op))
 select array_agg(id) into ids from c where s=(select max(s) from c);
 if ids is null or array_length(ids,1)>1 then  -- conflicto o sin regla: revisión manual, sin elegir arbitrariamente
  insert into plone27_tax_evaluations(event_key,rule_id,account_id,pathway,base,status) values(p_event_key,rid,p_account,'revision_manual',p_base,'review');
  insert into plone27_incidents(kind,detail) values('tax_rule_conflict',jsonb_build_object('event',p_event_key,'rule',p_code,'versions',ids)); return null; end if;
 v:=ids[1];
 if exists(select 1 from plone27_tax_exemptions where rule_id=rid and account_id=p_account and current_date>=valid_from and (valid_to is null or current_date<=valid_to)) then
  insert into plone27_tax_evaluations(event_key,rule_id,rule_version_id,account_id,pathway,base,amount,status) values(p_event_key,rid,v,p_account,p_pathway,p_base,0,'exempt'); return null; end if;
 amt:=plone27_tax_calc(v,p_base);
 insert into plone27_tax_evaluations(event_key,rule_id,rule_version_id,account_id,pathway,base,amount) values(p_event_key,rid,v,p_account,p_pathway,p_base,amt) returning id into ev;
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'tax_issue','evaluation',ev::text);
 insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date,evaluation_id) values(v,p_account,p_base,amt,p_due,ev) returning id into rid; return rid; end $$;

create or replace function plone27_tax_pay(p_key text,p_receipt uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; dl jsonb; ds numeric; lines jsonb; tx uuid; begin
 select t.*,ru.collector_account col,ru.id rule into r from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id where t.id=p_receipt for update of t;
 if r.status='paid' then return r.paid_tx; end if; if r.status<>'issued' then raise exception 'Recibo no cobrable'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('account',account_id,'dir','credit','amount',round(r.amount*pct/100,2))),'[]'),coalesce(sum(round(r.amount*pct/100,2)),0) into dl,ds from plone27_tax_distribution where rule_id=r.rule;
 lines:=jsonb_build_array(jsonb_build_object('account',r.account_id,'dir','debit','amount',r.amount))||dl;
 if r.amount-ds>0 then lines:=lines||jsonb_build_object('account',r.col,'dir','credit','amount',r.amount-ds); end if;
 tx:=plone27_post(p_key,'tax_payment',null,lines,p_actor);
 update plone27_tax_receipts set status='paid',paid_tx=tx where id=p_receipt; return tx; end $$;  -- 'pagado' solo tras contabilizar

-- REGULARIZACIONES RETROACTIVAS
create table if not exists plone27_tax_adjustments(id uuid primary key default gen_random_uuid(), receipt_id uuid not null references plone27_tax_receipts, new_version_id uuid not null references plone27_tax_rule_versions,
 original_amount numeric(18,2), corrected_amount numeric(18,2), diff numeric(18,2), status text default 'simulated' check(status in('simulated','approved','executed')),
 created_by uuid, approved_by uuid, adj_receipt uuid, adj_tx uuid, unique(receipt_id,new_version_id));
create or replace function plone27_adjust_simulate(p_receipt uuid,p_version uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r plone27_tax_receipts; v plone27_tax_rule_versions; c numeric; aid uuid; begin
 select * into r from plone27_tax_receipts where id=p_receipt; select * into v from plone27_tax_rule_versions where id=p_version and status='published';
 if v.id is null or v.retro_mode='prohibited' then raise exception 'La regla no permite retroactividad'; end if;
 if r.created_at::date<v.valid_from or (v.valid_to is not null and r.created_at::date>v.valid_to) then raise exception 'Recibo fuera del ámbito de vigencia'; end if;
 c:=plone27_tax_calc(p_version,r.base);
 insert into plone27_tax_adjustments(receipt_id,new_version_id,original_amount,corrected_amount,diff,created_by) values(p_receipt,p_version,r.amount,c,c-r.amount,p_actor) returning plone27_tax_adjustments.id into aid; return aid; end $$;
create or replace function plone27_adjust_approve(p_adj uuid,p_actor uuid) returns void language sql security definer set search_path=public as
$$ update plone27_tax_adjustments set status='approved',approved_by=p_actor where id=p_adj and status='simulated' $$;
create or replace function plone27_adjust_execute(p_adj uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare a plone27_tax_adjustments; r plone27_tax_receipts; mode text; col uuid; rid uuid; tx uuid; begin
 select * into a from plone27_tax_adjustments where id=p_adj for update; if a.status='executed' then return coalesce(a.adj_tx,a.adj_receipt); end if;
 select retro_mode into mode from plone27_tax_rule_versions where id=a.new_version_id;
 if a.status<>'approved' and mode<>'automatic' then raise exception 'Requiere aprobación'; end if;
 select * into r from plone27_tax_receipts where id=a.receipt_id;
 if a.diff>0 then
  insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date) values(a.new_version_id,r.account_id,r.base,a.diff,current_date+30) returning id into rid;
  update plone27_tax_adjustments set status='executed',adj_receipt=rid where id=p_adj; return rid;
 elsif a.diff<0 then
  if r.status<>'paid' or r.refunded-a.diff>r.amount then raise exception 'Devolución excede lo cobrado o recibo no pagado'; end if;
  select ru.collector_account into col from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id where v.id=r.rule_version_id;
  tx:=plone27_post('adj:'||p_adj,'tax_refund',null,jsonb_build_array(jsonb_build_object('account',col,'dir','debit','amount',-a.diff),jsonb_build_object('account',r.account_id,'dir','credit','amount',-a.diff)),p_actor);
  update plone27_tax_receipts set refunded=refunded-a.diff where id=r.id;
  update plone27_tax_adjustments set status='executed',adj_tx=tx where id=p_adj; return tx; end if;
 update plone27_tax_adjustments set status='executed' where id=p_adj; return null; end $$;

-- TARJETAS
create table if not exists plone27_card_designs(id uuid primary key default gen_random_uuid(), name text not null, tier text not null check(tier in('free','premium','commissioned','limited')),
 price numeric(18,2) not null default 0, license_fee numeric(18,2) not null default 0, revenue_account uuid references plone27_accounts, owner uuid,
 status text not null default 'draft' check(status in('draft','submitted','review','approved','rejected')), elements jsonb not null default '{}',
 check(not (elements ?| array['pan','cvv','chip','banda','antena','stripe','antenna','limit','status','balance'])));  -- el diseño no toca datos de seguridad ni permisos
create table if not exists plone27_design_purchases(design_id uuid references plone27_card_designs, account_id uuid references plone27_accounts, tx uuid, primary key(design_id,account_id));
create table if not exists plone27_cards(id uuid primary key default gen_random_uuid(), account_id uuid not null references plone27_accounts, kind text not null check(kind in('digital','physical','credit')),
 status text not null default 'active' check(status in('active','blocked','closed')), design_id uuid references plone27_card_designs, credit_limit numeric(18,2));
create table if not exists plone27_card_charges(id uuid primary key default gen_random_uuid(), card_id uuid not null references plone27_cards, merchant_account uuid not null references plone27_accounts,
 amount numeric(18,2) not null check(amount>0), status text not null default 'authorized' check(status in('authorized','billed','settled','released')), reservation_id uuid references plone27_reservations, at timestamptz default now());
create or replace function plone27_design_step(p_design uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare o text; begin
 select status into o from plone27_card_designs where id=p_design for update;
 if (o,p_to) not in(('draft','submitted'),('submitted','review'),('review','approved'),('review','rejected'),('rejected','draft')) then raise exception 'Transición no permitida'; end if;
 update plone27_card_designs set status=p_to where id=p_design; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'design_step','design',p_design::text,to_jsonb(p_to)); end $$;
create or replace function plone27_design_buy(p_key text,p_design uuid,p_account uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_card_designs; tx uuid; t numeric; begin
 select * into d from plone27_card_designs where id=p_design; if d.status<>'approved' then raise exception 'Diseño no aprobado'; end if;
 t:=d.price+d.license_fee; if t>0 then tx:=plone27_transfer(p_key,p_account,d.revenue_account,t,'Diseño '||d.name,p_actor); end if;
 insert into plone27_design_purchases values(p_design,p_account,tx) on conflict do nothing; return tx; end $$;
create or replace function plone27_card_authorize(p_card uuid,p_amount numeric,p_merchant uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; res uuid; ch uuid; begin
 select * into c from plone27_cards where id=p_card for update; if c.status<>'active' then raise exception 'Tarjeta no activa'; end if;
 if c.kind='credit' then
  if coalesce((select sum(amount) from plone27_card_charges where card_id=p_card and status in('authorized','billed')),0)+p_amount>coalesce(c.credit_limit,0) then raise exception 'Límite de crédito superado'; end if;
 else if plone27_available(c.account_id)<p_amount then raise exception 'Saldo insuficiente'; end if;
  insert into plone27_reservations(account_id,amount,reason) values(c.account_id,p_amount,'card auth') returning id into res; end if;
 insert into plone27_card_charges(card_id,merchant_account,amount,reservation_id) values(p_card,p_merchant,p_amount,res) returning id into ch; return ch; end $$;
create or replace function plone27_card_settle(p_key text,p_charge uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ch plone27_card_charges; c plone27_cards; tx uuid; begin
 select * into ch from plone27_card_charges where id=p_charge for update; if ch.status<>'authorized' then raise exception 'Cargo ya procesado'; end if;
 select * into c from plone27_cards where id=ch.card_id;
 if c.kind='credit' then update plone27_card_charges set status='billed' where id=p_charge; return null; end if;  -- crédito: consumo ≠ liquidación
 update plone27_reservations set status='released' where id=ch.reservation_id;
 tx:=plone27_transfer(p_key,c.account_id,ch.merchant_account,ch.amount,'Tarjeta',p_actor); update plone27_card_charges set status='settled' where id=p_charge; return tx; end $$;
create or replace function plone27_card_close_cycle(p_key text,p_card uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; lines jsonb; tot numeric; begin
 select * into c from plone27_cards where id=p_card for update;
 select sum(amount) into tot from plone27_card_charges where card_id=p_card and status='billed'; if coalesce(tot,0)=0 then return null; end if;
 select jsonb_build_array(jsonb_build_object('account',c.account_id,'dir','debit','amount',tot))||jsonb_agg(jsonb_build_object('account',m,'dir','credit','amount',s)) into lines
  from(select merchant_account m,sum(amount) s from plone27_card_charges where card_id=p_card and status='billed' group by 1)q;
 update plone27_card_charges set status='settled' where card_id=p_card and status='billed';
 return plone27_post(p_key,'credit_cycle',null,lines,p_actor); end $$;

-- PROGRAMADAS
create table if not exists plone27_scheduled(id uuid primary key default gen_random_uuid(), from_account uuid references plone27_accounts, to_account uuid references plone27_accounts,
 amount numeric(18,2) not null check(amount>0), run_at timestamptz not null, recurrence interval, status text default 'active' check(status in('active','done','cancelled')), memo text);
create or replace function plone27_run_scheduled(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare s record; n int:=0; begin
 for s in select * from plone27_scheduled where status='active' and run_at<=now() order by run_at for update skip locked loop
  begin perform plone27_transfer_fee('sch:'||s.id||':'||s.run_at,s.from_account,s.to_account,s.amount,s.memo,p_actor); n:=n+1;
   if s.recurrence is null then update plone27_scheduled set status='done' where id=s.id; else update plone27_scheduled set run_at=run_at+recurrence where id=s.id; end if;
  exception when others then insert into plone27_incidents(kind,detail) values('scheduled_failed',jsonb_build_object('id',s.id,'err',sqlerrm)); end;
 end loop; return n; end $$;

-- SUBVENCIONES Y BONOS
alter table plone27_grant_programs add column if not exists funding_account uuid references plone27_accounts;
alter table plone27_justifications drop constraint plone27_justifications_status_check, add check(status in('pending','approved','paid','rejected')) not valid;
create or replace function plone27_justify(p_grant uuid,p_tx uuid,p_invoice text,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; spent numeric; jid uuid; begin
 select * into g from plone27_grants where id=p_grant for update;
 select sum(e.amount) into spent from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.transaction_id=p_tx and e.account_id=g.beneficiary_account and e.direction='debit' and t.status='posted';
 if coalesce(spent,0)<p_amount then raise exception 'Transacción no elegible o importe excesivo'; end if;
 if coalesce((select sum(amount) from plone27_justifications where grant_id=p_grant and status<>'rejected'),0)+p_amount>g.granted then raise exception 'Supera lo concedido'; end if;
 insert into plone27_justifications(grant_id,transaction_id,invoice_ref,amount) values(p_grant,p_tx,p_invoice,p_amount) returning plone27_justifications.id into jid; return jid; end $$;  -- unique(transaction_id/invoice) impide justificar dos veces
create or replace function plone27_reimburse(p_key text,p_just uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare j plone27_justifications; g plone27_grants; f uuid; tx uuid; begin
 select * into j from plone27_justifications where id=p_just for update; if j.status not in('pending','approved') then raise exception 'Ya pagada o rechazada'; end if;
 select * into g from plone27_grants where id=j.grant_id for update; select funding_account into f from plone27_grant_programs where id=g.program_id;
 if j.status='pending' then update plone27_grants set approved=approved+j.amount where id=g.id; update plone27_justifications set status='approved' where id=p_just; end if;
 if plone27_available(f)<j.amount then return null; end if;   -- sin fondos: queda aprobado/pendiente, nunca "pagado"
 tx:=plone27_transfer(p_key,f,g.beneficiary_account,j.amount,'Reembolso',p_actor);
 update plone27_grants set paid=paid+j.amount where id=g.id; update plone27_justifications set status='paid' where id=p_just; return tx; end $$;

-- TESORERÍA
create table if not exists plone27_debts(id uuid primary key default gen_random_uuid(), account_id uuid references plone27_accounts, principal numeric(18,2) not null, authorized_charges numeric(18,2) default 0,
 paid numeric(18,2) default 0, due_date date, disputed boolean default false, authorized_by uuid not null, reason text not null);

do $$ declare t text; begin for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%'
 and not exists(select 1 from pg_policies p where p.tablename=pg_tables.tablename and p.policyname='staff_read') loop
 execute format('alter table %I enable row level security',t);
 execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end loop; end $$;
grant execute on function plone27_transfer_fee,plone27_tax_issue,plone27_tax_pay,plone27_adjust_simulate,plone27_adjust_approve,plone27_adjust_execute,plone27_design_step,plone27_design_buy,
 plone27_card_authorize,plone27_card_settle,plone27_card_close_cycle,plone27_run_scheduled,plone27_justify,plone27_reimburse,plone27_reverse to service_role;

-- ==================== MIGRACIÓN (0003_plone27_numeracion.sql) ====================
-- Placeta One · numeración e identificadores, multibanco, API clients. Generado siempre en servidor.
create table if not exists plone27_numbering_formats(kind text not null, version int not null, prefix text not null check(prefix ~ '^PL27-[A-Z]{3}-$'),
 year_scoped boolean not null, width int not null check(width between 4 and 15), status text not null default 'draft' check(status in('draft','published')),
 reason text, author uuid, approved_by uuid, valid_from date not null default current_date, primary key(kind,version));
create table if not exists plone27_counters(kind text not null, scope text not null, last bigint not null, primary key(kind,scope));
create table if not exists plone27_issued_ids(identifier text primary key, kind text not null, at timestamptz default now());  -- nunca se reutilizan ni se borran
drop trigger if exists t_ids_ro on plone27_issued_ids;
create trigger t_ids_ro before update or delete on plone27_issued_ids for each row execute function plone27_immutable();
insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,status,reason) values
('TAR',1,'PL27-TAR-',false,8,'published','inicial'),('TRF',1,'PL27-TRF-',false,12,'published','inicial'),('OPE',1,'PL27-OPE-',false,12,'published','inicial'),('AUT',1,'PL27-AUT-',false,8,'published','inicial'),
('REC',1,'PL27-REC-',true,6,'published','inicial'),('LIQ',1,'PL27-LIQ-',true,6,'published','inicial'),('REG',1,'PL27-REG-',true,6,'published','inicial'),('SUB',1,'PL27-SUB-',true,6,'published','inicial'),
('BON',1,'PL27-BON-',true,6,'published','inicial'),('JUS',1,'PL27-JUS-',true,6,'published','inicial'),('REE',1,'PL27-REE-',true,6,'published','inicial'),('FAC',1,'PL27-FAC-',true,6,'published','inicial'),
('DEU',1,'PL27-DEU-',true,6,'published','inicial'),('INC',1,'PL27-INC-',true,6,'published','inicial')
on conflict do nothing;

create or replace function plone27_next_num(p_kind text,p_scope text,p_max bigint) returns bigint language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare n bigint; begin
 insert into plone27_counters values(p_kind,p_scope,1) on conflict(kind,scope) do update set last=plone27_counters.last+1 returning last into n;
 if n>p_max then raise exception 'Capacidad agotada (% / %)',p_kind,p_scope; end if; return n; end $$;
create or replace function plone27_next_id(p_kind text) returns text language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare f plone27_numbering_formats; sc text; n bigint; id text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and status='published' and valid_from<=current_date order by version desc limit 1;
 if not found then raise exception 'Formato % sin publicar',p_kind; end if;
 sc:=case when f.year_scoped then extract(year from current_date)::text else 'global' end;
 n:=plone27_next_num(p_kind||':v'||f.version,sc,(power(10,f.width)-1)::bigint);
 id:=f.prefix||case when f.year_scoped then sc||'-' else '' end||lpad(n::text,f.width,'0');
 insert into plone27_issued_ids(identifier,kind) values(id,p_kind); return id; end $$;

-- Configuración versionada: propuesta → simulación → publicación aprobada (no altera identificadores históricos)
create or replace function plone27_numbering_propose(p_kind text,p_prefix text,p_year boolean,p_width int,p_reason text,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare v int; begin
 select coalesce(max(version),0)+1 into v from plone27_numbering_formats where kind=p_kind;
 insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,reason,author) values(p_kind,v,p_prefix,p_year,p_width,p_reason,p_actor); return v; end $$;
create or replace function plone27_numbering_simulate(p_kind text,p_version int,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare f plone27_numbering_formats; s text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and version=p_version;
 s:=f.prefix||case when f.year_scoped then extract(year from current_date)||'-' else '' end||lpad('1',f.width,'0');
 return jsonb_build_object('sample',s,'collides',exists(select 1 from plone27_issued_ids where identifier=s),'capacity',power(10,f.width)-1); end $$;
create or replace function plone27_numbering_publish(p_kind text,p_version int,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
 if plone27_numbering_simulate(p_kind,p_version,p_actor)->>'collides'='true' then raise exception 'Colisión de formato'; end if;
 update plone27_numbering_formats set status='published',approved_by=p_actor,valid_from=current_date where kind=p_kind and version=p_version and status='draft';
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'numbering_publish',p_kind,p_version::text); end $$;

-- Referencias automáticas e inmutables en documentos
create or replace function plone27_set_ref() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare k text:=tg_argv[0]; begin
 if tg_table_name='plone27_grants' then select case p.kind when 'bono' then 'BON' else 'SUB' end into k from plone27_grant_programs p where p.id=new.program_id; end if;
 if new.ref is null then new.ref:=plone27_next_id(k); end if; return new; end $$;
create or replace function plone27_ref_lock() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if new.ref is distinct from old.ref then raise exception 'Referencia inmutable'; end if; return new; end $$;
do $$ declare x text[]; begin
 foreach x slice 1 in array array[['plone27_tax_receipts','REC'],['plone27_tax_adjustments','REG'],['plone27_grants','SUB'],['plone27_justifications','JUS'],['plone27_incidents','INC'],['plone27_debts','DEU'],['plone27_approvals','AUT']] loop
  execute format('alter table %I add column if not exists ref text unique',x[1]);
  execute format('drop trigger if exists t_ref on %I',x[1]); execute format('create trigger t_ref before insert on %I for each row execute function plone27_set_ref(%L)',x[1],x[2]);
  execute format('drop trigger if exists t_ref_lock on %I',x[1]); execute format('create trigger t_ref_lock before update on %I for each row execute function plone27_ref_lock()',x[1]); end loop; end $$;
alter table plone27_transactions add column if not exists ref text unique, add column if not exists transfer_ref text unique;
create or replace function plone27_tx_refs() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
 new.ref:=plone27_next_id('OPE'); if new.kind='transfer' then new.transfer_ref:=plone27_next_id('TRF'); end if; return new; end $$;
drop trigger if exists t_tx_refs on plone27_transactions;
create trigger t_tx_refs before insert on plone27_transactions for each row execute function plone27_tx_refs();
drop trigger if exists t_tx_ref_lock on plone27_transactions;
create trigger t_tx_ref_lock before update on plone27_transactions for each row execute function plone27_ref_lock();
alter table plone27_justifications add column if not exists reimb_ref text unique;
create or replace function plone27_reimb_ref() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
 if new.status='paid' and new.reimb_ref is null then new.reimb_ref:=plone27_next_id('REE'); end if; return new; end $$;
drop trigger if exists t_reimb on plone27_justifications;
create trigger t_reimb before update on plone27_justifications for each row execute function plone27_reimb_ref();

-- Entidades y cuentas PZ-EEEE-CCCC (servidor únicamente, inmutables)
do $$ begin alter table plone27_banks add constraint banks_code4 check(code ~ '^[0-9]{4}$') not valid; exception when duplicate_object then null; end $$;
insert into plone27_banks(code,name,status) values('0000','Placeta Administración','active')
on conflict do nothing;   -- entidad reservada (cuentas de sistema)
alter table plone27_accounts add column if not exists iban text unique;
create or replace function plone27_iban_guard() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if tg_op='INSERT' then
  if new.iban is null or new.iban !~ '^PZ-[0-9]{4}-[0-9]{4}$' or substr(new.iban,4,4) is distinct from (select code from plone27_banks where id=new.bank_id) then raise exception 'IBAN solo generado por servidor'; end if;
 elsif new.iban is distinct from old.iban or new.bank_id is distinct from old.bank_id then raise exception 'IBAN inmutable'; end if; return new; end $$;
drop trigger if exists t_iban on plone27_accounts;
create trigger t_iban before insert or update on plone27_accounts for each row execute function plone27_iban_guard();
create or replace function plone27_open_bank(p_name text,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare c text; id uuid; begin
 c:=lpad(plone27_next_num('BANK','global',9999)::text,4,'0'); insert into plone27_banks(code,name) values(c,p_name) returning plone27_banks.id into id; return jsonb_build_object('id',id,'code',c); end $$;
create or replace function plone27_open_account(p_bank uuid,p_kind text,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare vc text; i text; id uuid; begin
 select b.code into vc from plone27_banks b where b.id=p_bank and b.status='active'; if vc is null then raise exception 'Entidad inexistente o no activa'; end if;
 i:='PZ-'||vc||'-'||lpad(plone27_next_num('ACC',vc,9999)::text,4,'0');
 insert into plone27_accounts(bank_id,kind,name,owner_user,iban,allow_negative) values(p_bank,p_kind,p_name,p_owner,i,p_kind='system') returning plone27_accounts.id into id;
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'open_account','account',i); return jsonb_build_object('id',id,'iban',i); end $$;

-- Tarjetas: id administrativo PL27-TAR; número visible solo en pruebas; sin PAN/CVV almacenados
alter table plone27_cards drop constraint plone27_cards_status_check, add check(status in('active','suspended','blocked','closed')) not valid,
 add column if not exists card_ref text unique, add column if not exists is_test boolean not null default false, add column if not exists expires date, add column if not exists last4 text, add column if not exists pan_hash text unique;
create or replace function plone27_issue_card(p_account uuid,p_kind text,p_design uuid,p_limit numeric,p_test boolean,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r text; num text; cid uuid; begin
 if not exists(select 1 from plone27_accounts where id=p_account and status='active') then raise exception 'Cuenta no activa'; end if;
 if p_design is not null and not exists(select 1 from plone27_design_purchases where design_id=p_design and account_id=p_account) then raise exception 'Diseño no adquirido'; end if;
 r:=plone27_next_id('TAR');
 if p_test then num:=lpad(floor(random()*10000000000000000)::bigint::text,16,'0'); end if;
 insert into plone27_cards(account_id,kind,design_id,credit_limit,card_ref,is_test,expires,last4,pan_hash)
  values(p_account,p_kind,p_design,p_limit,r,p_test,current_date+interval '5 years',right(num,4),encode(sha256(convert_to(coalesce(num,r),'utf8')),'hex')) returning plone27_cards.id into cid;
 return jsonb_build_object('id',cid,'card_ref',r,'test_number',regexp_replace(num,'(\d{4})(?=\d)','\1 ','g')); end $$;  -- el número de prueba se devuelve una sola vez
create or replace function plone27_card_set_status(p_card uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare o text; begin
 select status into o from plone27_cards where id=p_card for update; if o='closed' then raise exception 'Tarjeta cancelada'; end if;
 update plone27_cards set status=p_to where id=p_card; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'card_status','card',p_card::text,to_jsonb(p_to)); end $$;
create or replace function plone27_card_renew(p_card uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare c plone27_cards; begin
 select * into c from plone27_cards where id=p_card; perform plone27_card_set_status(p_card,'closed',p_actor);
 return plone27_issue_card(c.account_id,c.kind,c.design_id,c.credit_limit,c.is_test,p_actor); end $$;

-- Multibanco: clientes API por entidad con scopes y límite de uso
create table if not exists plone27_api_clients(id uuid primary key default gen_random_uuid(), bank_id uuid not null references plone27_banks, name text not null,
 key_hash text unique not null, scopes text[] not null default '{}', rate_limit int not null default 60, active boolean not null default true, created_at timestamptz default now());
create table if not exists plone27_api_usage(client_id uuid references plone27_api_clients, minute timestamptz, hits int not null default 0, primary key(client_id,minute));
create or replace function plone27_rate_hit(p_client uuid) returns int language sql security definer set search_path=public as $$
 insert into plone27_api_usage values(p_client,date_trunc('minute',now()),1) on conflict(client_id,minute) do update set hits=plone27_api_usage.hits+1 returning hits $$;

do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t<>'plone27_api_clients' and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname<>'plone27_has_role' loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;

-- ==================== MIGRACIÓN (0004_plone27_pendientes.sql) ====================
-- Titulares y permisos por cuenta, Junior, límites diarios (aplicados en el libro, no eludibles)
create table if not exists plone27_account_members(account_id uuid references plone27_accounts, user_id uuid, role text not null check(role in('holder','coholder','authorized')), primary key(account_id,user_id));
create table if not exists plone27_juniors(account_id uuid primary key references plone27_accounts, birth_date date not null, guardian_user uuid not null, per_tx_limit numeric(18,2) not null);
create or replace function plone27_ledger_limits() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
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
drop trigger if exists t_limits on plone27_ledger_entries;
create trigger t_limits before insert on plone27_ledger_entries for each row execute function plone27_ledger_limits();
create or replace function plone27_staff_set(p_user uuid,p_role text,p_active boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
 insert into plone27_staff(user_id,role,active) values(p_user,p_role,p_active) on conflict(user_id) do update set role=p_role,active=p_active;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'staff_set','staff',p_user::text,jsonb_build_object('role',p_role,'active',p_active)); end $$;

-- Lotes y nóminas (cada elemento idempotente y aislado: uno fallido no bloquea el resto)
create table if not exists plone27_batches(id uuid primary key default gen_random_uuid(), kind text not null check(kind in('payroll','batch')), from_account uuid not null references plone27_accounts, status text not null default 'open' check(status in('open','done','partial')));
create table if not exists plone27_batch_items(id uuid primary key default gen_random_uuid(), batch_id uuid not null references plone27_batches, to_account uuid not null references plone27_accounts,
 amount numeric(18,2) not null check(amount>0), status text not null default 'pending' check(status in('pending','paid','failed')), error text);
create or replace function plone27_run_batch(p_batch uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b plone27_batches; i record; ok int:=0; ko int:=0; begin
 select * into b from plone27_batches where id=p_batch for update;
 for i in select * from plone27_batch_items where batch_id=p_batch and status in('pending','failed') order by id loop
  begin perform plone27_transfer_fee('batch:'||i.id,b.from_account,i.to_account,i.amount,b.kind,p_actor); update plone27_batch_items set status='paid',error=null where id=i.id; ok:=ok+1;
  exception when others then update plone27_batch_items set status='failed',error=sqlerrm where id=i.id; ko:=ko+1; end; end loop;
 update plone27_batches set status=case when ko=0 then 'done' else 'partial' end where id=p_batch; return jsonb_build_object('paid',ok,'failed',ko); end $$;

-- Facturas internas, liquidación bancaria y conciliación fiscal
create table if not exists plone27_invoices(id uuid primary key default gen_random_uuid(), ref text unique, account_id uuid references plone27_accounts, concept text, amount numeric(18,2) not null check(amount>0), status text default 'issued' check(status in('issued','paid','void')));
create table if not exists plone27_settlements(id uuid primary key default gen_random_uuid(), ref text unique, bank_id uuid not null references plone27_banks, period_from date not null, period_to date not null,
 evaluated numeric(18,2), collected numeric(18,2), pending numeric(18,2), refunded numeric(18,2), unique(bank_id,period_from,period_to));
drop trigger if exists t_ref on plone27_invoices;
create trigger t_ref before insert on plone27_invoices for each row execute function plone27_set_ref('FAC');
drop trigger if exists t_ref on plone27_settlements;
create trigger t_ref before insert on plone27_settlements for each row execute function plone27_set_ref('LIQ');
create or replace function plone27_settle_bank(p_bank uuid,p_from date,p_to date,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare sid uuid; begin
 select id into sid from plone27_settlements where bank_id=p_bank and period_from=p_from and period_to=p_to; if sid is not null then return sid; end if;
 insert into plone27_settlements(bank_id,period_from,period_to,evaluated,collected,pending,refunded)
  select p_bank,p_from,p_to,coalesce(sum(r.amount),0),coalesce(sum(r.amount) filter(where r.status='paid'),0),coalesce(sum(r.amount) filter(where r.status='issued'),0),coalesce(sum(r.refunded),0)
  from plone27_tax_receipts r join plone27_accounts a on a.id=r.account_id where a.bank_id=p_bank and r.created_at::date between p_from and p_to returning plone27_settlements.id into sid; return sid; end $$;

-- Deuda con origen autorizado
alter table plone27_debts add column if not exists creditor_account uuid references plone27_accounts;
create or replace function plone27_debt_pay(p_key text,p_debt uuid,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare d plone27_debts; tx uuid; begin
 select * into d from plone27_debts where id=p_debt for update; if d.disputed then raise exception 'Deuda en disputa: no se cobra'; end if;
 if d.paid+p_amount>d.principal+d.authorized_charges then raise exception 'Excede la deuda'; end if;
 tx:=plone27_transfer(p_key,d.account_id,d.creditor_account,p_amount,'Deuda '||d.ref,p_actor); update plone27_debts set paid=paid+p_amount where id=p_debt; return tx; end $$;

-- Tarjetas físicas: pedido → producción → envío → activación (suspendida hasta activar)
create table if not exists plone27_card_orders(id uuid primary key default gen_random_uuid(), card_id uuid not null unique references plone27_cards, status text not null default 'ordered' check(status in('ordered','produced','shipped','activated','cancelled')), updated_at timestamptz default now());
create or replace function plone27_card_order_step(p_card uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare o text; begin
 if p_to='ordered' then insert into plone27_card_orders(card_id) values(p_card); update plone27_cards set status='suspended' where id=p_card; return; end if;
 select status into o from plone27_card_orders where card_id=p_card for update;
 if (o,p_to) not in(('ordered','produced'),('produced','shipped'),('shipped','activated'),('ordered','cancelled'),('produced','cancelled')) then raise exception 'Transición de pedido no permitida'; end if;
 update plone27_card_orders set status=p_to,updated_at=now() where card_id=p_card; if p_to='activated' then update plone27_cards set status='active' where id=p_card; end if; end $$;

-- Previsión de caja
create or replace function plone27_cash_forecast(p_days int,p_actor uuid) returns jsonb language sql stable security definer set search_path=public as $$
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

-- ==================== MIGRACIÓN (0005_plone27_cierre.sql) ====================
-- Alcance por entidad para el personal
alter table plone27_staff add column if not exists bank_id uuid references plone27_banks;   -- null = global
create or replace function plone27_bank_visible(p_bank uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from plone27_staff s where s.user_id=auth.uid() and s.active and (s.bank_id is null or s.bank_id=p_bank)) $$;
drop policy staff_read on plone27_accounts;
create policy staff_read on plone27_accounts for select using (plone27_has_role(array['auditor','financiero','fiscal','financiacion','gestor_bancario','aprobador']) and plone27_bank_visible(bank_id));
drop view if exists plone27_account_balances cascade;
create view plone27_account_balances with(security_invoker=true) as
select a.id account_id, a.name, a.kind, a.status,
  coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) booked,
  coalesce((select sum(r.amount) from plone27_reservations r where r.account_id=a.id and r.status='active'),0) reserved, a.bank_id
from plone27_accounts a left join plone27_ledger_entries e on e.account_id=a.id group by a.id;

-- Doble aprobación (umbral configurable) y solicitudes de aprobación genéricas
create table if not exists plone27_config(key text primary key, value text not null);
insert into plone27_config values('dual_approval_threshold','1000')
on conflict do nothing;
create or replace function plone27_adjust_approve(p_adj uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
declare a plone27_tax_adjustments; begin
 select * into a from plone27_tax_adjustments where id=p_adj for update;
 if a.created_by is not distinct from p_actor and abs(a.diff)>=(select value::numeric from plone27_config where key='dual_approval_threshold') then raise exception 'Doble aprobación: debe aprobar otra persona'; end if;
 update plone27_tax_adjustments set status='approved',approved_by=p_actor where id=p_adj and status='simulated'; end $$;
create or replace function plone27_approval_request(p_subject text,p_subject_id uuid,p_reason text,p_actor uuid) returns uuid language sql security definer set search_path=public as
$$ insert into plone27_approvals(subject,subject_id,requested_by,reason) values(p_subject,p_subject_id,p_actor,p_reason) returning id $$;
create or replace function plone27_approval_decide(p_id uuid,p_approve boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 if exists(select 1 from plone27_approvals where id=p_id and requested_by is not distinct from p_actor) then raise exception 'El solicitante no puede aprobar su propia solicitud'; end if;
 update plone27_approvals set approved_by=p_actor,result=case when p_approve then 'approved' else 'rejected' end where id=p_id and result is null; end $$;

-- Tramos fiscales y pagos parciales
alter table plone27_tax_rule_versions drop constraint plone27_tax_rule_versions_method_check, add check(method in('percent','fixed','brackets')) not valid;
create table if not exists plone27_tax_brackets(version_id uuid not null references plone27_tax_rule_versions, from_amount numeric(18,2) not null, to_amount numeric(18,2), rate numeric(9,4) not null, primary key(version_id,from_amount));
create or replace function plone27_tax_calc(p_version uuid,p_base numeric) returns numeric language sql stable as $$
 select round(least(coalesce(v.max_amount,'infinity'),greatest(coalesce(v.min_amount,0),
  case v.method when 'percent' then p_base*v.rate/100 when 'fixed' then v.rate
   else coalesce((select sum((least(p_base,coalesce(b.to_amount,'infinity'))-b.from_amount)*b.rate/100) from plone27_tax_brackets b where b.version_id=v.id and p_base>b.from_amount),0) end)),2)
 from plone27_tax_rule_versions v where v.id=p_version $$;
alter table plone27_tax_receipts drop constraint plone27_tax_receipts_status_check, add check(status in('issued','partial','paid','rectified')) not valid, add column if not exists paid_amount numeric(18,2) not null default 0;
create or replace function plone27_tax_pay_partial(p_key text,p_receipt uuid,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; dl jsonb; ds numeric; lines jsonb; tx uuid; done boolean; begin
 select t.*,ru.collector_account col,ru.id rule into r from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id where t.id=p_receipt for update of t;
 if r.status not in('issued','partial') then raise exception 'Recibo no cobrable'; end if;
 if p_amount<=0 or r.paid_amount+p_amount>r.amount then raise exception 'Importe de pago inválido'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('account',account_id,'dir','credit','amount',round(p_amount*pct/100,2))),'[]'),coalesce(sum(round(p_amount*pct/100,2)),0) into dl,ds from plone27_tax_distribution where rule_id=r.rule;
 lines:=jsonb_build_array(jsonb_build_object('account',r.account_id,'dir','debit','amount',p_amount))||dl;
 if p_amount-ds>0 then lines:=lines||jsonb_build_object('account',r.col,'dir','credit','amount',p_amount-ds); end if;
 tx:=plone27_post(p_key,'tax_payment',null,lines,p_actor); done:=r.paid_amount+p_amount=r.amount;
 update plone27_tax_receipts set paid_amount=paid_amount+p_amount,status=case when done then 'paid' else 'partial' end,paid_tx=case when done then tx else paid_tx end where id=p_receipt; return tx; end $$;

-- Webhooks (outbox por entidad, firma HMAC) y alertas
create table if not exists plone27_webhooks(id uuid primary key default gen_random_uuid(), bank_id uuid not null references plone27_banks, url text not null check(url ~ '^https://'), secret text not null, events text[] not null default '{*}', active boolean not null default true);
create table if not exists plone27_outbox(id bigint generated always as identity primary key, event text not null, bank_ids uuid[] not null default '{}', payload jsonb, status text not null default 'pending' check(status in('pending','sent','failed')), attempts int not null default 0, created_at timestamptz default now());
create or replace function plone27_emit() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare b uuid[]; p jsonb; begin
 if new.action='post' then
  select array_agg(distinct a.bank_id) into b from plone27_accounts a where a.id in(select (x->>'account')::uuid from jsonb_array_elements(new.detail) x);
  select jsonb_build_object('operation',t.ref,'transfer',t.transfer_ref,'kind',t.kind) into p from plone27_transactions t where t.id=new.entity_id::uuid;
  insert into plone27_outbox(event,bank_ids,payload) values('transaction.posted',coalesce(b,'{}'),p); end if; return new; end $$;
drop trigger if exists t_emit on plone27_audit_log;
create trigger t_emit after insert on plone27_audit_log for each row execute function plone27_emit();
drop view if exists plone27_alerts cascade;
create view plone27_alerts with(security_invoker=true) as
 select 'incidencias_abiertas' alerta,count(*) n from plone27_incidents where status='open'
 union all select 'evaluaciones_en_revision',count(*) from plone27_tax_evaluations where status='review'
 union all select 'aprobaciones_pendientes',count(*) from plone27_approvals where result is null
 union all select 'lotes_con_fallos',count(*) from plone27_batch_items where status='failed'
 union all select 'webhooks_fallidos',count(*) from plone27_outbox where status='failed'
 union all select 'reembolsos_pendientes_de_fondos',count(*) from plone27_justifications where status='approved';

do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;

-- ==================== MIGRACIÓN (0006_plone27_configuracion.sql) ====================
-- Configuración central: global + sobrescritura por entidad dentro de límites centrales; historial y aprobación de cambios sensibles
create table if not exists plone27_settings(key text primary key, category text not null, description text not null, vtype text not null check(vtype in('number','boolean','text','enum')),
 allowed text[], min_v numeric, max_v numeric, value jsonb not null, sensitive boolean not null default false, bank_overridable boolean not null default true, version int not null default 1, updated_at timestamptz default now());
create table if not exists plone27_bank_settings(bank_id uuid not null references plone27_banks, key text not null references plone27_settings, value jsonb not null, primary key(bank_id,key));
create table if not exists plone27_setting_changes(id uuid primary key default gen_random_uuid(), key text not null references plone27_settings, bank_id uuid references plone27_banks, new_value jsonb not null, old_value jsonb,
 reason text not null, proposed_by uuid, approved_by uuid, status text not null default 'pending' check(status in('pending','applied','rejected')), at timestamptz default now());
insert into plone27_settings(key,category,description,vtype,allowed,min_v,max_v,value,sensitive,bank_overridable) values
('dual_approval_threshold','aprobaciones','Importe (Pz) desde el que una regularización exige otra persona','number',null,0,1000000,'1000',true,false),
('unpaid_negative_adjustment_policy','fiscalidad','Regularización a favor del usuario sobre recibo sin pagar','enum','{reject,credit_note,rectify}',null,null,'"reject"',true,true),
('default_receipt_due_days','fiscalidad','Días de vencimiento de recibos de ajuste','number',null,1,365,'30',false,true),
('late_penalty_enabled','fiscalidad','Permite recargos por mora (solo con norma autorizada)','boolean',null,null,null,'false',true,false),
('late_penalty_rule_code','fiscalidad','Código de la norma fiscal que define el recargo','text',null,null,null,'""',true,false),
('default_daily_limit','cuentas','Límite diario por defecto en Pz (0 = sin límite)','number',null,0,100000000,'0',false,true),
('junior_default_limit','cuentas','Límite por operación Junior sin ficha (Pz)','number',null,0,100000,'20',false,true),
('webhook_max_attempts','integraciones','Reintentos de webhook antes de marcar fallo','number',null,1,20,'5',false,false),
('api_default_rate_limit','integraciones','Peticiones por minuto de un cliente API nuevo','number',null,1,10000,'60',false,true)
on conflict do nothing;
create or replace function plone27_setting(p_key text,p_bank uuid default null) returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column declare v jsonb; begin
 select coalesce((select b.value from plone27_bank_settings b where b.bank_id=p_bank and b.key=p_key),s.value) into v from plone27_settings s where s.key=p_key;
 if v is null then raise exception 'Ajuste desconocido: %',p_key; end if; return v; end $$;
create or replace function plone27_setting_validate(p_key text,p_value jsonb) returns void language plpgsql stable as $$
#variable_conflict use_column declare s plone27_settings; begin
 select * into s from plone27_settings where key=p_key; if s.key is null then raise exception 'Ajuste desconocido'; end if;
 if s.vtype='number' then if jsonb_typeof(p_value)<>'number' or (p_value#>>'{}')::numeric<coalesce(s.min_v,-1e18) or (p_value#>>'{}')::numeric>coalesce(s.max_v,1e18) then raise exception 'Fuera de los límites centrales [% , %]',s.min_v,s.max_v; end if;
 elsif s.vtype='boolean' then if jsonb_typeof(p_value)<>'boolean' then raise exception 'Se esperaba booleano'; end if;
 elsif s.vtype='enum' then if not (p_value#>>'{}')=any(s.allowed) then raise exception 'Valor no permitido (%)',s.allowed; end if;
 elsif jsonb_typeof(p_value)<>'string' then raise exception 'Se esperaba texto'; end if; end $$;
create or replace function plone27_setting_apply(p_change uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare c plone27_setting_changes; begin
 select * into c from plone27_setting_changes where id=p_change and status='pending' for update; if c.id is null then return; end if;
 if c.bank_id is null then update plone27_settings set value=c.new_value,version=version+1,updated_at=now() where key=c.key;
 else insert into plone27_bank_settings values(c.bank_id,c.key,c.new_value) on conflict(bank_id,key) do update set value=c.new_value; end if;
 update plone27_setting_changes set status='applied',approved_by=coalesce(approved_by,p_actor) where id=p_change;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'setting_applied','setting',c.key,jsonb_build_object('bank',c.bank_id,'new',c.new_value)); end $$;
create or replace function plone27_setting_propose(p_key text,p_value jsonb,p_bank uuid,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_settings; id uuid; begin
 select * into s from plone27_settings where key=p_key; perform plone27_setting_validate(p_key,p_value);
 if p_bank is not null and not s.bank_overridable then raise exception 'Este ajuste solo es central'; end if; if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 insert into plone27_setting_changes(key,bank_id,new_value,old_value,reason,proposed_by) values(p_key,p_bank,p_value,plone27_setting(p_key,p_bank),p_reason,p_actor) returning plone27_setting_changes.id into id;
 if not s.sensitive then perform plone27_setting_apply(id,p_actor); end if; return id; end $$;
create or replace function plone27_setting_approve(p_change uuid,p_approve boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare c plone27_setting_changes; begin
 select * into c from plone27_setting_changes where id=p_change and status='pending'; if c.id is null then raise exception 'Cambio no pendiente'; end if;
 if c.proposed_by is not distinct from p_actor then raise exception 'El proponente no puede aprobar su propio cambio'; end if;
 if p_approve then update plone27_setting_changes set approved_by=p_actor where id=p_change; perform plone27_setting_apply(p_change,p_actor);
 else update plone27_setting_changes set status='rejected',approved_by=p_actor where id=p_change; end if; end $$;

-- Lo que antes estaba fijado en el código ahora lee la configuración
create or replace function plone27_adjust_approve(p_adj uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare a plone27_tax_adjustments; begin
 select * into a from plone27_tax_adjustments where id=p_adj for update;
 if a.created_by is not distinct from p_actor and abs(a.diff)>=(plone27_setting('dual_approval_threshold')#>>'{}')::numeric then raise exception 'Doble aprobación: debe aprobar otra persona'; end if;
 update plone27_tax_adjustments set status='approved',approved_by=p_actor where id=p_adj and status='simulated'; end $$;
create or replace function plone27_ledger_limits() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare a plone27_accounts; k text; j plone27_juniors; used numeric; dl numeric; jl numeric; begin
 if new.direction<>'debit' then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','tax_refund') then return new; end if;
 select * into a from plone27_accounts where id=new.account_id;
 dl:=coalesce(a.daily_limit,nullif((plone27_setting('default_daily_limit',a.bank_id)#>>'{}')::numeric,0));
 if dl is not null then
  select coalesce(sum(e.amount),0) into used from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.account_id=new.account_id and e.direction='debit' and t.kind<>'reversal' and e.created_at::date=current_date;
  if used+new.amount>dl then raise exception 'Límite diario superado (% Pz)',dl; end if; end if;
 if a.kind='junior' then select * into j from plone27_juniors where account_id=a.id; jl:=coalesce(j.per_tx_limit,(plone27_setting('junior_default_limit',a.bank_id)#>>'{}')::numeric);
  if new.amount>jl then raise exception 'Junior: supera el límite por operación; requiere tutor'; end if; end if; return new; end $$;
alter table plone27_tax_receipts add column if not exists disputed boolean not null default false;
create or replace function plone27_adjust_execute(p_adj uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare a plone27_tax_adjustments; r plone27_tax_receipts; mode text; col uuid; rid uuid; tx uuid; pol text; bk uuid; begin
 select * into a from plone27_tax_adjustments where id=p_adj for update; if a.status='executed' then return coalesce(a.adj_tx,a.adj_receipt); end if;
 select retro_mode into mode from plone27_tax_rule_versions where id=a.new_version_id;
 if a.status<>'approved' and mode<>'automatic' then raise exception 'Requiere aprobación'; end if;
 select * into r from plone27_tax_receipts where id=a.receipt_id; select bank_id into bk from plone27_accounts where id=r.account_id;
 if a.diff>0 then
  insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date) values(a.new_version_id,r.account_id,r.base,a.diff,current_date+(plone27_setting('default_receipt_due_days',bk)#>>'{}')::int) returning id into rid;
  update plone27_tax_adjustments set status='executed',adj_receipt=rid where id=p_adj; return rid;
 elsif a.diff<0 then
  if r.status in('issued','partial') then
   pol:=plone27_setting('unpaid_negative_adjustment_policy',bk)#>>'{}';
   if pol='reject' then raise exception 'Política: recibo pendiente; no se admite ajuste a favor'; end if;
   if pol='credit_note' then
    if r.paid_amount>a.corrected_amount then raise exception 'Lo pagado excede el importe corregido'; end if;
    update plone27_tax_receipts set amount=a.corrected_amount,status=case when r.paid_amount=a.corrected_amount then 'paid' else r.status end where id=r.id; rid:=r.id;
   else
    if r.paid_amount>0 then raise exception 'Con pagos parciales usa nota de crédito'; end if;
    update plone27_tax_receipts set status='rectified' where id=r.id;
    insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date,original_receipt) values(a.new_version_id,r.account_id,r.base,a.corrected_amount,r.due_date,r.id) returning id into rid; end if;
   update plone27_tax_adjustments set status='executed',adj_receipt=rid where id=p_adj; return rid; end if;
  if r.refunded-a.diff>r.amount then raise exception 'Devolución excede lo cobrado'; end if;
  select ru.collector_account into col from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id where v.id=r.rule_version_id;
  tx:=plone27_post('adj:'||p_adj,'tax_refund',null,jsonb_build_array(jsonb_build_object('account',col,'dir','debit','amount',-a.diff),jsonb_build_object('account',r.account_id,'dir','credit','amount',-a.diff)),p_actor);
  update plone27_tax_receipts set refunded=refunded-a.diff where id=r.id; update plone27_tax_adjustments set status='executed',adj_tx=tx where id=p_adj; return tx; end if;
 update plone27_tax_adjustments set status='executed' where id=p_adj; return null; end $$;
create or replace function plone27_apply_late_penalties(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare code text; n int:=0; r record; x uuid; begin
 if not (plone27_setting('late_penalty_enabled'))::boolean then return 0; end if;
 code:=plone27_setting('late_penalty_rule_code')#>>'{}'; if code='' then raise exception 'Recargo activado sin norma autorizada'; end if;
 for r in select t.*,a.bank_id from plone27_tax_receipts t join plone27_accounts a on a.id=t.account_id where t.status in('issued','partial') and t.due_date<current_date and not t.disputed and t.original_receipt is null loop
  x:=plone27_tax_issue(code,r.account_id,r.amount-r.paid_amount,'penalty:'||r.id,null,'recibo',current_date+(plone27_setting('default_receipt_due_days',r.bank_id)#>>'{}')::int,p_actor); if x is not null then n:=n+1; end if; end loop; return n; end $$;

do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;

-- ==================== MIGRACIÓN (0007_plone27_productos.sql) ====================
-- Productos financieros por entidad: cuentas (personal, empresa, compartida, Junior), tarjetas, crédito interno y servicios
create table if not exists plone27_products(id uuid primary key default gen_random_uuid(), code text unique not null, bank_id uuid not null references plone27_banks,
 kind text not null check(kind in('account_personal','account_business','account_shared','account_junior','card_digital','card_physical','card_credit','internal_credit','service')),
 name text not null, description text, status text not null default 'draft' check(status in('draft','active','retired')),
 daily_limit numeric(18,2), credit_limit numeric(18,2), monthly_fee numeric(18,2) not null default 0 check(monthly_fee>=0), fee_account uuid references plone27_accounts,
 interest_rate numeric(9,4) not null default 0, min_age int, requires_guardian boolean not null default false, valid_from date, valid_to date,
 terms jsonb not null default '{}', approved_by uuid, created_by uuid, created_at timestamptz default now());
alter table plone27_accounts add column if not exists product_id uuid references plone27_products;
create or replace function plone27_product_guard() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if new.status is distinct from old.status then
  if (old.status,new.status) not in(('draft','active'),('active','retired'),('draft','retired')) then raise exception 'Transición de producto % → % no permitida',old.status,new.status; end if;
  if new.status='active' and new.approved_by is null then raise exception 'Activar un producto requiere aprobación registrada'; end if; end if; return new; end $$;
drop trigger if exists t_product_guard on plone27_products;
create trigger t_product_guard before update on plone27_products for each row execute function plone27_product_guard();
create or replace function plone27_open_account_p(p_product uuid,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare p plone27_products; k text; r jsonb; begin
 select * into p from plone27_products where id=p_product and status='active' and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
 if p.id is null then raise exception 'Producto no disponible'; end if; if p.kind not like 'account\_%' then raise exception 'No es un producto de cuenta'; end if;
 k:=case p.kind when 'account_personal' then 'personal' when 'account_business' then 'business' when 'account_shared' then 'shared' else 'junior' end;
 r:=plone27_open_account(p.bank_id,k,p_name,p_owner,p_actor);
 update plone27_accounts set product_id=p_product,daily_limit=coalesce(p.daily_limit,daily_limit) where id=(r->>'id')::uuid; return r; end $$;
create or replace function plone27_charge_product_fees(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare n int:=0; a record; begin
 for a in select ac.id,p.monthly_fee fee,p.fee_account from plone27_accounts ac join plone27_products p on p.id=ac.product_id where ac.status='active' and p.monthly_fee>0 and p.fee_account is not null loop
  begin perform plone27_transfer('pfee:'||a.id||':'||to_char(now(),'YYYY-MM'),a.id,a.fee_account,a.fee,'Cuota de producto',p_actor); n:=n+1;
  exception when others then insert into plone27_incidents(kind,detail) values('product_fee_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end; end loop; return n; end $$;
do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;

-- ==================== MIGRACIÓN (0008_plone27_motor.sql) ====================
-- MOTOR: idempotencia estricta, titularidad, crédito interno con intereses, reservas, reversos coherentes, auditoría inmutable
alter table plone27_transactions add column if not exists req_hash text;
create or replace function plone27_post(p_key text,p_kind text,p_memo text,p_lines jsonb,p_actor uuid,p_reverses uuid default null)
returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
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
create or replace function plone27_transfer_user(p_key text,p_user uuid,p_from uuid,p_to uuid,p_amount numeric,p_memo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
 if not exists(select 1 from plone27_account_members where account_id=p_from and user_id=p_user) and not exists(select 1 from plone27_juniors where account_id=p_from and guardian_user=p_user)
  then raise exception 'El usuario no está autorizado en la cuenta de origen'; end if;
 return plone27_transfer_fee(p_key,p_from,p_to,p_amount,p_memo,p_actor); end $$;

-- Reservas manuales (programadas, retenciones)
create or replace function plone27_reserve(p_account uuid,p_amount numeric,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare rid uuid; begin
 perform 1 from plone27_accounts where id=p_account for update;
 if p_amount<=0 or plone27_available(p_account)<p_amount then raise exception 'Saldo disponible insuficiente'; end if;
 insert into plone27_reservations(account_id,amount,reason) values(p_account,p_amount,p_reason) returning plone27_reservations.id into rid; return rid; end $$;
create or replace function plone27_release(p_res uuid,p_actor uuid) returns void language sql security definer set search_path=public as
$$ update plone27_reservations set status='released' where id=p_res and status='active' $$;

-- Crédito interno: descubierto con límite e intereses mensuales idempotentes
alter table plone27_accounts add column if not exists credit_limit numeric(18,2) not null default 0;
create or replace function plone27_credit_floor() returns trigger language plpgsql security definer set search_path=public as $$
declare a plone27_accounts; k text; bal numeric; begin
 if new.direction<>'debit' then return new; end if; select * into a from plone27_accounts where id=new.account_id;
 if a.kind='system' or not a.allow_negative then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','interest') then return new; end if;
 select coalesce(sum(case when direction='credit' then amount else -amount end),0) into bal from plone27_ledger_entries where account_id=new.account_id;
 if bal-new.amount < -a.credit_limit then raise exception 'Límite de crédito superado'; end if; return new; end $$;
drop trigger if exists t_credit_floor on plone27_ledger_entries;
create trigger t_credit_floor before insert on plone27_ledger_entries for each row execute function plone27_credit_floor();
create or replace function plone27_open_account_p(p_product uuid,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare p plone27_products; k text; r jsonb; begin
 select * into p from plone27_products where id=p_product and status='active' and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
 if p.id is null then raise exception 'Producto no disponible'; end if;
 if p.kind not like 'account\_%' and p.kind<>'internal_credit' then raise exception 'No es un producto de cuenta'; end if;
 k:=case p.kind when 'account_business' then 'business' when 'account_shared' then 'shared' when 'account_junior' then 'junior' else 'personal' end;
 r:=plone27_open_account(p.bank_id,k,p_name,p_owner,p_actor);
 update plone27_accounts set product_id=p_product,daily_limit=coalesce(p.daily_limit,daily_limit),allow_negative=(p.kind='internal_credit'),credit_limit=case when p.kind='internal_credit' then coalesce(p.credit_limit,0) else 0 end where id=(r->>'id')::uuid; return r; end $$;
create or replace function plone27_accrue_interest(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare n int:=0; a record; i numeric; begin
 for a in select ac.id,p.interest_rate r,p.fee_account fa,b.booked from plone27_accounts ac join plone27_products p on p.id=ac.product_id join plone27_account_balances b on b.account_id=ac.id
  where p.kind='internal_credit' and p.interest_rate>0 and p.fee_account is not null and ac.status='active' and b.booked<0 loop
  i:=round(-a.booked*a.r/100/12,2);
  if i>0 then begin perform plone27_post('int:'||a.id||':'||to_char(now(),'YYYY-MM'),'interest','Interés mensual',jsonb_build_array(jsonb_build_object('account',a.id,'dir','debit','amount',i),jsonb_build_object('account',a.fa,'dir','credit','amount',i)),p_actor); n:=n+1;
   exception when others then insert into plone27_incidents(kind,detail) values('interest_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end; end if; end loop; return n; end $$;

-- Reversos coherentes y recibos
create or replace function plone27_on_reversed() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if new.status='reversed' and old.status<>'reversed' then
  if new.kind='reversal' then raise exception 'No se puede revertir una reversión'; end if;
  update plone27_tax_receipts r set paid_amount=greatest(r.paid_amount-d.s,0),paid_tx=null,status=case when r.paid_amount-d.s>0 then 'partial' else 'issued' end
   from (select coalesce(sum(amount),0) s from plone27_ledger_entries where transaction_id=new.id and direction='debit') d where r.paid_tx=new.id; end if; return new; end $$;
drop trigger if exists t_on_reversed on plone27_transactions;
create trigger t_on_reversed before update on plone27_transactions for each row execute function plone27_on_reversed();
create or replace function plone27_receipt_paid() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if new.status='paid' and new.paid_amount<new.amount then new.paid_amount:=new.amount; end if; return new; end $$;
drop trigger if exists t_receipt_paid on plone27_tax_receipts;
create trigger t_receipt_paid before update on plone27_tax_receipts for each row execute function plone27_receipt_paid();
drop trigger if exists t_audit_ro on plone27_audit_log;
create trigger t_audit_ro before update or delete on plone27_audit_log for each row execute function plone27_immutable();

do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;

-- ==================== MIGRACIÓN (0009_plone27_normas.sql) ====================
-- Clientes (DIP) y normas configurables: recargos, disputas y condiciones de deuda. Ámbito: global < banco < cliente = DIP. Topes centrales no superables.
create table if not exists plone27_customers(id uuid primary key default gen_random_uuid(), dip text unique not null check(dip ~ '^[A-Z0-9-]{4,24}$'), full_name text not null, bank_id uuid references plone27_banks,
 user_id uuid, status text not null default 'active' check(status in('active','blocked')), created_at timestamptz default now());
alter table plone27_accounts add column if not exists customer_id uuid references plone27_customers;
create table if not exists plone27_policies(id uuid primary key default gen_random_uuid(), ref text unique, kind text not null check(kind in('penalty','dispute','debt_terms')), name text not null,
 scope text not null check(scope in('global','bank','customer','dip')), bank_id uuid references plone27_banks, customer_id uuid references plone27_customers, dip text, params jsonb not null default '{}',
 valid_from date not null default current_date, valid_to date, status text not null default 'draft' check(status in('draft','published','retired')), reason text, approved_by uuid, created_by uuid, created_at timestamptz default now());
insert into plone27_settings(key,category,description,vtype,min_v,max_v,value,sensitive,bank_overridable) values
('penalty_max_pct','normas','Tope central (%) de un recargo por mora','number',0,100,'10',true,false),
('dispute_max_days','normas','Tope central de días para resolver una disputa','number',1,365,'90',true,false),
('debt_max_interest_pct','normas','Tope central del interés mensual (%) de una deuda','number',0,100,'5',true,false)
on conflict do nothing;
insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,status,reason) values('DIS',1,'PL27-DIS-',true,6,'published','inicial'),('POL',1,'PL27-POL-',true,6,'published','inicial')
on conflict do nothing;
drop trigger if exists t_ref on plone27_policies;
create trigger t_ref before insert on plone27_policies for each row execute function plone27_set_ref('POL');
create or replace function plone27_policy_guard() returns trigger language plpgsql as $$
#variable_conflict use_column declare p jsonb:=new.params; begin
 if tg_op='UPDATE' and old.status='published' and (new.params is distinct from old.params or new.scope is distinct from old.scope or new.bank_id is distinct from old.bank_id or new.customer_id is distinct from old.customer_id or new.dip is distinct from old.dip or new.kind is distinct from old.kind)
  then raise exception 'Norma publicada inmutable: crea una nueva'; end if;
 if (new.scope='bank' and new.bank_id is null) or (new.scope='customer' and new.customer_id is null) or (new.scope='dip' and new.dip is null) then raise exception 'La norma no indica su destinatario'; end if;
 if new.kind='penalty' then
  if coalesce(p->>'type','') not in('percent','fixed') or p->>'value' is null or (p->>'value')::numeric<0 then raise exception 'Recargo: indica type (percent|fixed) y value'; end if;
  if p->>'type'='percent' and (p->>'value')::numeric>(plone27_setting('penalty_max_pct')#>>'{}')::numeric then raise exception 'Supera el tope central de recargo'; end if;
 elsif new.kind='dispute' then
  if coalesce((p->>'max_days')::int,0)<1 or (p->>'max_days')::int>(plone27_setting('dispute_max_days')#>>'{}')::numeric then raise exception 'Disputa: max_days fuera del tope central'; end if;
 elsif coalesce((p->>'interest_pct')::numeric,0)>(plone27_setting('debt_max_interest_pct')#>>'{}')::numeric then raise exception 'Supera el tope central de interés'; end if;
 if new.status='published' and new.approved_by is null then raise exception 'Publicar exige aprobación registrada'; end if; return new; end $$;
drop trigger if exists t_policy_guard on plone27_policies;
create trigger t_policy_guard before insert or update on plone27_policies for each row execute function plone27_policy_guard();
-- Resolución: la más específica gana; empate en el mismo nivel = incidencia y sin aplicar (nunca se elige al azar)
create or replace function plone27_policy_resolve(p_kind text,p_account uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare a plone27_accounts; v_dip text; ids uuid[]; r jsonb; begin
 select * into a from plone27_accounts where id=p_account; select c.dip into v_dip from plone27_customers c where c.id=a.customer_id;
 with c as(select p.id,case p.scope when 'global' then 1 when 'bank' then 2 else 3 end lvl from plone27_policies p where p.kind=p_kind and p.status='published' and current_date>=p.valid_from and (p.valid_to is null or current_date<=p.valid_to)
  and (p.scope='global' or (p.scope='bank' and p.bank_id=a.bank_id) or (p.scope='customer' and p.customer_id=a.customer_id) or (p.scope='dip' and p.dip=v_dip)))
 select array_agg(c.id) into ids from c where c.lvl=(select max(lvl) from c);
 if ids is null then return null; end if;
 if array_length(ids,1)>1 then insert into plone27_incidents(kind,detail) values('policy_conflict',jsonb_build_object('kind',p_kind,'account',p_account,'policies',ids)); return null; end if;
 select p.params||jsonb_build_object('policy',p.id,'approved_by',p.approved_by) into r from plone27_policies p where p.id=ids[1]; return r; end $$;
-- Deuda: condiciones aplicadas por norma
alter table plone27_debts add column if not exists origin text unique;
create or replace function plone27_debt_terms() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare pol jsonb; begin
 if new.account_id is null then return new; end if; pol:=plone27_policy_resolve('debt_terms',new.account_id); if pol is null then return new; end if;
 if tg_op='INSERT' and pol->>'max_principal' is not null and new.principal>(pol->>'max_principal')::numeric then raise exception 'Supera el principal máximo de la norma (%)',pol->>'max_principal'; end if;
 if tg_op='UPDATE' and new.paid>old.paid and pol->>'allow_partial'='false' and new.paid<new.principal+new.authorized_charges then raise exception 'La norma no permite pagos parciales'; end if; return new; end $$;
drop trigger if exists t_debt_terms on plone27_debts;
create trigger t_debt_terms before insert or update on plone27_debts for each row execute function plone27_debt_terms();
-- Recargos por mora: solo con norma publicada aplicable; se crean como deuda con origen autorizado y una sola vez por recibo
create or replace function plone27_apply_late_penalties(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int:=0; r record; pol jsonb; amt numeric; begin
 if not (plone27_setting('late_penalty_enabled'))::boolean then return 0; end if;
 for r in select t.id,t.ref,t.account_id,t.amount,t.paid_amount,t.due_date,ru.collector_account col from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id
  where t.status in('issued','partial') and not t.disputed and t.original_receipt is null and not exists(select 1 from plone27_debts d where d.origin='penalty:'||t.id) loop
  pol:=plone27_policy_resolve('penalty',r.account_id); continue when pol is null or r.due_date+coalesce((pol->>'grace_days')::int,0)>=current_date;
  amt:=case pol->>'type' when 'percent' then round((r.amount-r.paid_amount)*(pol->>'value')::numeric/100,2) else (pol->>'value')::numeric end;
  if pol ? 'max_amount' then amt:=least(amt,(pol->>'max_amount')::numeric); end if;
  if amt>0 then insert into plone27_debts(account_id,creditor_account,principal,due_date,reason,authorized_by,origin) values(r.account_id,r.col,amt,current_date+30,'Recargo por mora del recibo '||r.ref,(pol->>'approved_by')::uuid,'penalty:'||r.id); n:=n+1; end if; end loop; return n; end $$;
-- Disputas: congelan el cobro, tienen plazo por norma y la resuelve otra persona
create table if not exists plone27_disputes(id uuid primary key default gen_random_uuid(), ref text unique, subject_type text not null check(subject_type in('receipt','debt')), subject_id uuid not null, account_id uuid references plone27_accounts,
 reason text not null, status text not null default 'open' check(status in('open','upheld','rejected','withdrawn')), opened_by uuid, opened_at timestamptz default now(), due_at timestamptz, resolution text, resolved_by uuid, resolved_at timestamptz);
create unique index if not exists plone27_disputes_subject_type_subject_id_idx on plone27_disputes(subject_type,subject_id) where status='open';
drop trigger if exists t_ref on plone27_disputes;
create trigger t_ref before insert on plone27_disputes for each row execute function plone27_set_ref('DIS');
create or replace function plone27_dispute_open(p_type text,p_subject uuid,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare acc uuid; pol jsonb; did uuid; begin
 if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 if p_type='receipt' then select account_id into acc from plone27_tax_receipts where id=p_subject; else select account_id into acc from plone27_debts where id=p_subject; end if;
 if acc is null then raise exception 'Objeto inexistente'; end if;
 pol:=plone27_policy_resolve('dispute',acc);
 insert into plone27_disputes(subject_type,subject_id,account_id,reason,opened_by,due_at) values(p_type,p_subject,acc,p_reason,p_actor,now()+make_interval(days=>coalesce((pol->>'max_days')::int,30))) returning plone27_disputes.id into did;
 if p_type='receipt' then update plone27_tax_receipts set disputed=true where id=p_subject; else update plone27_debts set disputed=true where id=p_subject; end if; return did; end $$;
create or replace function plone27_dispute_resolve(p_id uuid,p_outcome text,p_note text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare d plone27_disputes; begin
 if p_outcome not in('upheld','rejected','withdrawn') then raise exception 'Resultado no válido'; end if;
 select * into d from plone27_disputes where id=p_id and status='open' for update; if d.id is null then raise exception 'Disputa no abierta'; end if;
 if p_outcome<>'withdrawn' and d.opened_by is not distinct from p_actor then raise exception 'La disputa debe resolverla otra persona'; end if;
 if d.subject_type='receipt' then update plone27_tax_receipts set disputed=false,status=case when p_outcome='upheld' then 'rectified' else status end where id=d.subject_id;
 else update plone27_debts set disputed=false,authorized_charges=case when p_outcome='upheld' then 0 else authorized_charges end,principal=case when p_outcome='upheld' then paid else principal end where id=d.subject_id; end if;
 update plone27_disputes set status=p_outcome,resolution=p_note,resolved_by=p_actor,resolved_at=now() where id=p_id;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'dispute_resolved','dispute',p_id::text,jsonb_build_object('outcome',p_outcome)); end $$;
drop view if exists plone27_alerts cascade;
create view plone27_alerts with(security_invoker=true) as
 select 'incidencias_abiertas' alerta,count(*) n from plone27_incidents where status='open'
 union all select 'evaluaciones_en_revision',count(*) from plone27_tax_evaluations where status='review'
 union all select 'aprobaciones_pendientes',count(*) from plone27_approvals where result is null
 union all select 'lotes_con_fallos',count(*) from plone27_batch_items where status='failed'
 union all select 'webhooks_fallidos',count(*) from plone27_outbox where status='failed'
 union all select 'reembolsos_pendientes_de_fondos',count(*) from plone27_justifications where status='approved'
 union all select 'disputas_vencidas',count(*) from plone27_disputes where status='open' and due_at<now();
do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;

-- ==================== MIGRACIÓN (0010_plone27_junior_estado.sql) ====================
-- JUNIOR: ficha de cliente con control parental heredado, aislamiento de cuentas habituales, membresía mensual; INFORMES de integridad y seguridad
create table if not exists plone27_junior_profiles(customer_id uuid primary key references plone27_customers, birth_date date not null, guardian_user uuid not null, per_tx_limit numeric(18,2), daily_limit numeric(18,2), monthly_limit numeric(18,2),
 card_enabled boolean not null default true, locked boolean not null default false);
do $$ begin alter table plone27_products add constraint products_junior_compat check(kind<>'account_junior' or (coalesce(credit_limit,0)=0 and interest_rate=0 and requires_guardian)) not valid; exception when duplicate_object then null; end $$;
create or replace function plone27_account_compat() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if new.kind='junior' and (new.allow_negative or new.credit_limit>0) then raise exception 'Una cuenta Junior no admite descubierto ni crédito'; end if; return new; end $$;
drop trigger if exists t_account_compat on plone27_accounts;
create trigger t_account_compat before insert or update on plone27_accounts for each row execute function plone27_account_compat();
create or replace function plone27_card_compat() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare a plone27_accounts; j plone27_junior_profiles; begin
 select * into a from plone27_accounts where id=new.account_id; if a.kind<>'junior' then return new; end if;
 if new.kind='credit' then raise exception 'Una cuenta Junior no admite tarjeta de crédito'; end if;
 select * into j from plone27_junior_profiles where customer_id=a.customer_id; if j.customer_id is not null and not j.card_enabled then raise exception 'El control parental no permite tarjetas'; end if; return new; end $$;
drop trigger if exists t_card_compat on plone27_cards;
create trigger t_card_compat before insert on plone27_cards for each row execute function plone27_card_compat();
-- Membresía mensual (renovable por la app mediante API)
create table if not exists plone27_subscriptions(id uuid primary key default gen_random_uuid(), account_id uuid unique not null references plone27_accounts, product_id uuid references plone27_products,
 status text not null default 'past_due' check(status in('active','past_due','expired','cancelled')), period_start date, period_end date not null default current_date, auto_renew boolean not null default true,
 renewals int not null default 0, last_tx uuid references plone27_transactions, created_at timestamptz default now());
create or replace function plone27_sub_create() returns trigger language plpgsql as $$
#variable_conflict use_column begin
 if new.kind='junior' and new.product_id is not null and old.product_id is null then insert into plone27_subscriptions(account_id,product_id) values(new.id,new.product_id) on conflict do nothing; end if; return new; end $$;
drop trigger if exists t_sub_create on plone27_accounts;
create trigger t_sub_create after update of product_id on plone27_accounts for each row execute function plone27_sub_create();
insert into plone27_settings(key,category,description,vtype,min_v,max_v,value,sensitive,bank_overridable) values
('junior_renewal_window_days','junior','Días antes del vencimiento en que se puede renovar la membresía','number',0,31,'5',false,true),
('junior_membership_grace_days','junior','Días de gracia tras vencer antes de pasar a «expirada»','number',0,60,'5',false,true)
on conflict do nothing;
create or replace function plone27_user_can(p_user uuid,p_account uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from plone27_account_members where account_id=p_account and user_id=p_user) or exists(select 1 from plone27_juniors where account_id=p_account and guardian_user=p_user)
  or exists(select 1 from plone27_accounts a join plone27_junior_profiles j on j.customer_id=a.customer_id where a.id=p_account and j.guardian_user=p_user) $$;
create or replace function plone27_subscription_renew(p_account uuid,p_user uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
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
create or replace function plone27_subscriptions_sweep(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s record; r jsonb; ren int:=0; exp int:=0; g int:=(plone27_setting('junior_membership_grace_days')#>>'{}')::int; begin
 for s in select * from plone27_subscriptions where status in('active','past_due') and period_end<=current_date loop
  if s.auto_renew then r:=plone27_subscription_renew(s.account_id,null,p_actor); if (r->>'renewed')='true' then ren:=ren+1; continue; end if; end if;
  if s.period_end+g<current_date then update plone27_subscriptions set status='expired' where id=s.id; exp:=exp+1; else update plone27_subscriptions set status='past_due' where id=s.id and status='active'; end if; end loop;
 return jsonb_build_object('renewed',ren,'expired',exp); end $$;
-- Reglas Junior en el libro: control parental heredado de la ficha + membresía vigente + sin cuentas habituales
create or replace function plone27_junior_profile() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
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
drop trigger if exists t_junior_profile on plone27_ledger_entries;
create trigger t_junior_profile before insert on plone27_ledger_entries for each row execute function plone27_junior_profile();
create or replace function plone27_junior_counterparty() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
 if exists(select 1 from (select distinct n.transaction_id from new_rows n join plone27_transactions t on t.id=n.transaction_id where t.kind<>'reversal') x
  where exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind='junior')
   and exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind in('personal','shared','business')))
 then raise exception 'Cuenta Junior: no puede enviar ni recibir de cuentas de clientes habituales'; end if; return null; end $$;
drop trigger if exists t_junior_cp on plone27_ledger_entries;
create trigger t_junior_cp after insert on plone27_ledger_entries referencing new table as new_rows for each statement execute function plone27_junior_counterparty();
create or replace function plone27_ledger_limits() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
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
create or replace function plone27_integrity_report() returns jsonb language sql stable security definer set search_path=public as $$
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
create or replace function plone27_security_report() returns jsonb language sql stable security definer set search_path=public as $$
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

-- ==================== MIGRACIÓN (0011_plone27_finanzas.sql) ====================
-- Placeta One · 0011 · Finanzas automatizadas
-- Cierra lo que faltaba respecto a 0001–0010: cuenta principal y de impuestos por entidad (globales),
-- calendario de pagos a plazos y suscripciones con fecha de cálculo, interés automático, mora por segundo
-- (Art. 4.3), autocobro, nóminas con cotizaciones (Art. 4.5), SMI, RBU (Art. 4.6–4.7) y ejecución diaria.
-- Idempotente: se puede ejecutar sobre una base ya migrada hasta 0010.
-- Los datos de la norma (tipos, tramos, cuentas de reserva) van en supabase/seeds/0011_seed_norma_tributos_2027.sql,
-- no aquí: acceptance.sql crea IGF e IRM con esos mismos códigos y chocaría.

-- ========== 1. ENTIDAD: cuenta principal, cuenta de impuestos y cuentas no embargables ==========
alter table plone27_banks add column if not exists main_account uuid references plone27_accounts,
  add column if not exists tax_account uuid references plone27_accounts;
alter table plone27_accounts add column if not exists collectable boolean not null default true;  -- false = no embargable (cartera RBU)

create or replace function plone27_bank_accounts_guard() returns trigger language plpgsql as $$
#variable_conflict use_column begin
  if new.main_account is not null and not exists(select 1 from plone27_accounts a where a.id=new.main_account and a.bank_id=new.id)
    then raise exception 'La cuenta principal debe pertenecer a la propia entidad'; end if;
  if new.tax_account is not null and not exists(select 1 from plone27_accounts a where a.id=new.tax_account and a.bank_id=new.id)
    then raise exception 'La cuenta de impuestos debe pertenecer a la propia entidad'; end if;
  return new; end $$;
drop trigger if exists t_bank_accounts on plone27_banks;
drop trigger if exists t_bank_accounts on plone27_banks;
create trigger t_bank_accounts before insert or update on plone27_banks for each row execute function plone27_bank_accounts_guard();

create or replace function plone27_bank_set_accounts(p_bank uuid,p_main uuid,p_tax uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  update plone27_banks set main_account=p_main,tax_account=p_tax where id=p_bank;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'bank_accounts','bank',p_bank::text,jsonb_build_object('main',p_main,'tax',p_tax));
end $$;

create or replace function plone27_main_account(p_bank uuid) returns uuid language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  select main_account into acc from plone27_banks where id=p_bank;
  if acc is null then raise exception 'La entidad no tiene cuenta principal configurada'; end if; return acc; end $$;

create or replace function plone27_reserve_account() returns uuid language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_reserva';
  if acc is null then raise exception 'Falta la Cuenta de Reserva del Grupo (ejecuta el seed 0011)'; end if; return acc; end $$;

create or replace function plone27_collectable(p_account uuid,p_amount numeric) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_accounts a where a.id=p_account and a.status='active' and a.collectable) and plone27_available(p_account)>=p_amount $$;

-- Suma meses a una fecha conservando el día de anclaje (31 → 30/28 si el mes es más corto)
create or replace function plone27_add_months(p_from date,p_months int,p_anchor int) returns date language plpgsql stable as $$
#variable_conflict use_column
declare base date; last_day int; begin
  base:=(p_from+make_interval(months=>p_months))::date;
  last_day:=extract(day from (date_trunc('month',base)+interval '1 month - 1 day'))::int;
  return make_date(extract(year from base)::int,extract(month from base)::int,least(p_anchor,last_day)); end $$;

-- ========== 2. AJUSTES NUEVOS (lo que la norma no fija queda en 0 = inactivo hasta que lo apruebe quien corresponda) ==========
insert into plone27_settings(key,category,description,vtype,allowed,min_v,max_v,value,sensitive,bank_overridable) values
('tasas_transferencia_max_pct','tasas','Tope (%) de la tasa de transferencia (Art. 4.3)','number',null,0,12,'12',true,false),
('interes_anual_pct','finanzas','Interés anual de cuotas y crédito (automático; cada entidad lo fija dentro del tope)','number',null,0,60,'0',true,true),
('demora_anual_pct','fiscalidad','Interés de demora anual (Art. 4.3; lo aprueba el Departamento Económico)','number',null,0,60,'0',true,false),
('demora_habilitada','fiscalidad','Activa el interés de demora por segundo sobre recibos (Art. 4.3). Alternativa a los recargos escalonados del Art. T57','boolean',null,null,null,'false',true,false),
('periodo_gracia_mora_dias','fiscalidad','Días tras notificación o vencimiento antes de devengar mora','number',null,0,60,'7',true,false),
('autocobro_habilitado','cobros','Cobro automático en fecha de recibos, cuotas, suscripciones y deudas','boolean',null,null,null,'true',true,true),
('rbu_semanal_pz','bienestar','Importe semanal de la RBU (Pz)','number',null,0,1000,'5',true,false),
('smi_semanal_completa_pz','laboral','SMI semanal para jornada completa (Pz)','number',null,0,100000,'150',true,false),
('dia_nomina','laboral','Día del mes en que se paga la nómina (supuesto: confirmar)','number',null,1,28,'28',false,true)
on conflict(key) do nothing;

-- Tope de la tasa de transferencia (Art. 4.3: nunca superior al 12 %)
create or replace function plone27_fee_cap() returns trigger language plpgsql as $$
#variable_conflict use_column begin
  if new.method='percent' and new.rate>(plone27_setting('tasas_transferencia_max_pct')#>>'{}')::numeric
    then raise exception 'La tasa de transferencia supera el tope central (Art. 4.3)'; end if;
  return new; end $$;
drop trigger if exists t_fee_cap on plone27_fee_rules;
drop trigger if exists t_fee_cap on plone27_fee_rules;
create trigger t_fee_cap before insert or update on plone27_fee_rules for each row execute function plone27_fee_cap();

-- ========== 3. MOTOR FISCAL: tramo fijo para cotizaciones, publicación con aprobador, impuestos de entidad ==========
alter table plone27_tax_rule_versions drop constraint if exists plone27_tax_rule_versions_method_check;
do $$ begin alter table plone27_tax_rule_versions add constraint plone27_tax_rule_versions_method_check
  check(method in('percent','fixed','brackets','bracket_flat')) not valid; exception when duplicate_object then null; end $$;  -- bracket_flat: todo el bruto al tipo de su tramo (Art. 4.5)

create or replace function plone27_tax_calc(p_version uuid,p_base numeric) returns numeric language sql stable as $$
 select round(least(coalesce(v.max_amount,'infinity'),greatest(coalesce(v.min_amount,0),
   case v.method
    when 'percent' then p_base*v.rate/100
    when 'fixed' then v.rate
    when 'brackets' then coalesce((select sum((least(p_base,coalesce(b.to_amount,'infinity'))-b.from_amount)*b.rate/100)
                                    from plone27_tax_brackets b where b.version_id=v.id and p_base>b.from_amount),0)
    else coalesce((select p_base*b.rate/100 from plone27_tax_brackets b where b.version_id=v.id and p_base>b.from_amount
                   and (b.to_amount is null or p_base<=b.to_amount) limit 1),0)
   end)),2)
 from plone27_tax_rule_versions v where v.id=p_version $$;

-- Publicar exige un aprobador distinto del autor (gobernanza de la Junta)
create or replace function plone27_tax_publish(p_version uuid,p_approver uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v plone27_tax_rule_versions; begin
  select * into v from plone27_tax_rule_versions where id=p_version for update;
  if v.id is null or v.status<>'draft' then raise exception 'La versión no está en borrador'; end if;
  if p_approver is null or p_approver is not distinct from v.author then raise exception 'Publicar exige un aprobador distinto del autor'; end if;
  update plone27_tax_rule_versions set status='published',approver=p_approver,published_at=now() where id=p_version;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_publish','tax_version',p_version::text,jsonb_build_object('approver',p_approver));
end $$;

create or replace function plone27_active_version(p_code text,p_date date) returns uuid language sql stable security definer set search_path=public as $$
  select v.id from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id
  where r.code=p_code and v.status='published' and v.scope_bank is null and v.scope_op is null
    and p_date>=v.valid_from and (v.valid_to is null or p_date<=v.valid_to)
  order by v.valid_from desc,v.version desc limit 1 $$;

-- Impuesto de entidad: se cobra de la cuenta de impuestos de la entidad (o de la principal). Cada entidad decide de dónde paga.
create or replace function plone27_tax_issue_bank(p_code text,p_bank uuid,p_base numeric,p_event_key text,p_op text,p_pathway text,p_due date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  select coalesce(tax_account,main_account) into acc from plone27_banks where id=p_bank;
  if acc is null then raise exception 'La entidad no tiene cuenta de impuestos ni principal'; end if;
  return plone27_tax_issue(p_code,acc,p_base,p_event_key,p_op,p_pathway,p_due,p_actor); end $$;

-- ========== 4. CALENDARIO DE PAGOS: cuotas (interés automático de la entidad) y suscripciones ==========
create table if not exists plone27_plans(
  id uuid primary key default gen_random_uuid(),
  idem_key text unique not null,
  kind text not null check(kind in('installment','subscription')),
  bank_id uuid not null references plone27_banks,
  debtor_account uuid not null references plone27_accounts,
  beneficiary_account uuid not null references plone27_accounts,
  lender_account uuid references plone27_accounts,                  -- cuenta principal de la entidad (solo cuotas)
  principal numeric(18,2) not null check(principal>0),              -- cuotas: capital; suscripción: importe por periodo
  annual_rate_pct numeric(9,4) not null default 0 check(annual_rate_pct>=0),  -- snapshot automático al crear
  installments int check(installments>0),
  start_date date not null,                                         -- fecha de cálculo: desde aquí se devenga el interés
  anchor_day int not null check(anchor_day between 1 and 31),
  next_due date,
  status text not null default 'active' check(status in('active','past_due','completed','cancelled')),
  approved_by uuid not null, created_by uuid, created_at timestamptz not null default now(),
  check((kind='installment' and installments is not null and lender_account is not null)
     or (kind='subscription' and installments is null and lender_account is null)));
create table if not exists plone27_plan_items(
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references plone27_plans,
  seq int not null, due_date date not null,
  principal_part numeric(18,2) not null check(principal_part>=0),
  interest_part numeric(18,2) not null default 0 check(interest_part>=0),
  status text not null default 'pending' check(status in('pending','paid')),
  attempts int not null default 0, paid_tx uuid references plone27_transactions, paid_at timestamptz,
  unique(plan_id,seq));

-- Amortización francesa (cuota constante). Interés mensual = tipo anual / 12, sobre el saldo vivo. La última cuota absorbe el redondeo.
create or replace function plone27_plan_schedule(p_principal numeric,p_rate numeric,p_n int,p_start date,p_anchor int)
returns table(seq int,due_date date,principal_part numeric,interest_part numeric) language plpgsql stable as $$
#variable_conflict use_column
declare m numeric:=p_rate/1200; cuota numeric; saldo numeric:=p_principal; i_p numeric; c_p numeric; k int; begin
  if p_n<1 then raise exception 'Número de cuotas inválido'; end if;
  cuota:=case when m=0 then round(p_principal/p_n,2) else round(p_principal*m/(1-power(1+m,-p_n)),2) end;
  for k in 1..p_n loop
    i_p:=round(saldo*m,2);
    c_p:=case when k=p_n then saldo else cuota-i_p end;
    saldo:=saldo-c_p;
    seq:=k; due_date:=plone27_add_months(p_start,k,p_anchor); principal_part:=c_p; interest_part:=i_p;
    return next;
  end loop; end $$;

-- Crea un plan. Cuotas: la cuenta principal de la entidad desembolsa el capital al beneficiario y cobra capital+interés en cada cuota.
create or replace function plone27_plan_create(p_key text,p_kind text,p_debtor uuid,p_beneficiary uuid,p_principal numeric,p_installments int,p_start date,p_approved_by uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare bk uuid; rate numeric:=0; lender uuid; pid uuid; anchor int; s record; begin
  if p_approved_by is null then raise exception 'Crear un plan exige aprobación registrada'; end if;
  if p_kind not in('installment','subscription') then raise exception 'Tipo de plan no válido'; end if;
  select id into pid from plone27_plans where idem_key=p_key; if pid is not null then return pid; end if;
  select bank_id into bk from plone27_accounts where id=p_debtor and status='active';
  if bk is null then raise exception 'Cuenta deudora no activa'; end if;
  if p_beneficiary=p_debtor or not exists(select 1 from plone27_accounts where id=p_beneficiary and status='active') then raise exception 'Beneficiario no válido'; end if;
  anchor:=extract(day from p_start)::int;
  if p_kind='installment' then
    if coalesce(p_installments,0)<1 then raise exception 'Indica el número de cuotas'; end if;
    rate:=(plone27_setting('interes_anual_pct',bk)#>>'{}')::numeric;
    if rate/12>(plone27_setting('debt_max_interest_pct')#>>'{}')::numeric then raise exception 'El interés supera el tope central'; end if;
    lender:=plone27_main_account(bk);
  elsif p_installments is not null then raise exception 'Una suscripción no tiene número de cuotas'; end if;
  insert into plone27_plans(idem_key,kind,bank_id,debtor_account,beneficiary_account,lender_account,principal,annual_rate_pct,installments,start_date,anchor_day,next_due,approved_by,created_by)
  values(p_key,p_kind,bk,p_debtor,p_beneficiary,lender,p_principal,rate,p_installments,p_start,anchor,
         case when p_kind='subscription' then p_start else plone27_add_months(p_start,1,anchor) end,p_approved_by,p_actor)
  returning id into pid;
  if p_kind='installment' then
    for s in select * from plone27_plan_schedule(p_principal,rate,p_installments,p_start,anchor) loop
      insert into plone27_plan_items(plan_id,seq,due_date,principal_part,interest_part) values(pid,s.seq,s.due_date,s.principal_part,s.interest_part);
    end loop;
    perform plone27_post('plan:'||p_key,'installment_disbursal','Desembolso a plazos',jsonb_build_array(
      jsonb_build_object('account',lender,'dir','debit','amount',p_principal),
      jsonb_build_object('account',p_beneficiary,'dir','credit','amount',p_principal)),p_actor);
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'plan_create','plan',pid::text,jsonb_build_object('kind',p_kind,'principal',p_principal,'rate',rate));
  return pid;
end $$;

-- Cobro de cuotas y suscripciones vencidas. Sin fondos: queda pendiente y se reintenta cada día (sin duplicar).
create or replace function plone27_plans_collect(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare it record; pl record; amt numeric; tx uuid; cobradas int:=0; pendientes int:=0; begin
  for it in select i.*,p.debtor_account,p.lender_account from plone27_plan_items i join plone27_plans p on p.id=i.plan_id
    where i.status='pending' and i.due_date<=current_date and p.status in('active','past_due') order by i.due_date,i.id loop
    amt:=it.principal_part+it.interest_part;
    if not plone27_collectable(it.debtor_account,amt) then
      update plone27_plan_items set attempts=attempts+1 where id=it.id; pendientes:=pendientes+1; continue;
    end if;
    begin
      tx:=plone27_post('cuota:'||it.id,'installment_payment','Cuota '||it.seq,jsonb_build_array(
        jsonb_build_object('account',it.debtor_account,'dir','debit','amount',amt),
        jsonb_build_object('account',it.lender_account,'dir','credit','amount',amt)),p_actor);
      update plone27_plan_items set status='paid',paid_tx=tx,paid_at=now() where id=it.id; cobradas:=cobradas+1;
    exception when others then
      insert into plone27_incidents(kind,detail) values('cuota_fallida',jsonb_build_object('item',it.id,'err',sqlerrm)); pendientes:=pendientes+1;
    end;
  end loop;
  for pl in select * from plone27_plans where kind='subscription' and status in('active','past_due') and next_due<=current_date order by next_due loop
    if not plone27_collectable(pl.debtor_account,pl.principal) then
      update plone27_plans set status='past_due' where id=pl.id; pendientes:=pendientes+1; continue;
    end if;
    begin
      tx:=plone27_transfer('sub:'||pl.id||':'||pl.next_due,pl.debtor_account,pl.beneficiary_account,pl.principal,'Suscripción',p_actor);
      update plone27_plans set next_due=plone27_add_months(pl.next_due,1,pl.anchor_day),status='active' where id=pl.id; cobradas:=cobradas+1;
    exception when others then
      insert into plone27_incidents(kind,detail) values('suscripcion_fallida',jsonb_build_object('plan',pl.id,'err',sqlerrm)); pendientes:=pendientes+1;
    end;
  end loop;
  update plone27_plans p set status='completed' where p.kind='installment' and p.status in('active','past_due')
    and not exists(select 1 from plone27_plan_items i where i.plan_id=p.id and i.status='pending');
  update plone27_plans p set status='past_due' where p.kind='installment' and p.status='active'
    and exists(select 1 from plone27_plan_items i where i.plan_id=p.id and i.status='pending' and i.due_date<current_date);
  return jsonb_build_object('cobradas',cobradas,'pendientes',pendientes);
end $$;

-- ========== 5. MORA POR SEGUNDO (Art. 4.3): el devengo se calcula por segundos y se convierte en deuda automática ==========
create table if not exists plone27_late_accruals(source text not null check(source in('item','receipt')), ref uuid not null,
  accrued_until timestamptz not null, primary key(source,ref));

-- Devengo: capital pendiente × tipo anual × segundos / 365 días. Se liquida al céntimo; si no llega a 0,01 no se pierde: se acumula.
create or replace function plone27_mora_run(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare it record; rc record; rate numeric; grace int; since timestamptz; secs numeric; amt numeric; gen int:=0; begin
  rate:=(plone27_setting('demora_anual_pct')#>>'{}')::numeric; grace:=(plone27_setting('periodo_gracia_mora_dias')#>>'{}')::int;
  if rate<=0 then return jsonb_build_object('devengos',0,'motivo','tipo de demora sin aprobar'); end if;
  -- cuotas vencidas: la mora corre desde vencimiento + gracia
  for it in select i.id,i.due_date,i.principal_part+i.interest_part pend,p.debtor_account deb,p.lender_account len,p.approved_by apr
    from plone27_plan_items i join plone27_plans p on p.id=i.plan_id
    where i.status='pending' and now()>(i.due_date+grace)::timestamptz loop
    select accrued_until into since from plone27_late_accruals where source='item' and ref=it.id;
    since:=coalesce(since,(it.due_date+grace)::timestamptz);
    secs:=extract(epoch from now()-since); amt:=round(it.pend*rate/100*secs/31536000,2);
    if amt>=0.01 then
      insert into plone27_debts(account_id,creditor_account,principal,due_date,reason,authorized_by,origin)
        values(it.deb,it.len,amt,current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int,'Interés de demora sobre cuota',it.apr,
               'demora:item:'||it.id||':'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSUS'));
      insert into plone27_late_accruals(source,ref,accrued_until) values('item',it.id,now())
        on conflict(source,ref) do update set accrued_until=excluded.accrued_until;
      gen:=gen+1;
    end if;
  end loop;
  -- recibos fiscales impagos: solo si el Departamento Económico activó el interés de demora (alternativa a T57)
  if (plone27_setting('demora_habilitada'))::boolean then
    for rc in select t.id,t.account_id,t.created_at,t.amount-t.paid_amount pend,ru.collector_account col,v.approver apr
      from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id
      where t.status in('issued','partial') and not t.disputed and now()>t.created_at+make_interval(days=>grace) loop
      select accrued_until into since from plone27_late_accruals where source='receipt' and ref=rc.id;
      since:=coalesce(since,rc.created_at+make_interval(days=>grace));
      secs:=extract(epoch from now()-since); amt:=round(rc.pend*rate/100*secs/31536000,2);
      if amt>=0.01 then
        insert into plone27_debts(account_id,creditor_account,principal,due_date,reason,authorized_by,origin)
          values(rc.account_id,rc.col,amt,current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int,'Interés de demora sobre recibo fiscal',rc.apr,
                 'demora:receipt:'||rc.id||':'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSUS'));
        insert into plone27_late_accruals(source,ref,accrued_until) values('receipt',rc.id,now())
          on conflict(source,ref) do update set accrued_until=excluded.accrued_until;
        gen:=gen+1;
      end if;
    end loop;
  end if;
  return jsonb_build_object('devengos',gen);
end $$;

-- ========== 6. AUTOCOBRO: recibos fiscales y deudas (nunca de cuentas no embargables) ==========
create or replace function plone27_autocollect_taxes(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; n int:=0; begin
  if not (plone27_setting('autocobro_habilitado'))::boolean then return 0; end if;
  for r in select t.id,t.account_id,t.amount-t.paid_amount pend from plone27_tax_receipts t
    where t.status in('issued','partial') and not t.disputed and t.due_date<=current_date order by t.due_date,t.id loop
    continue when not plone27_collectable(r.account_id,r.pend);
    begin perform plone27_tax_pay_partial('auto:tax:'||r.id||':'||r.pend,r.id,r.pend,p_actor); n:=n+1;
    exception when others then insert into plone27_incidents(kind,detail) values('autocobro_fallido',jsonb_build_object('recibo',r.id,'err',sqlerrm)); end;
  end loop; return n; end $$;

create or replace function plone27_autocollect_debts(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; n int:=0; begin
  if not (plone27_setting('autocobro_habilitado'))::boolean then return 0; end if;
  for r in select d.id,d.account_id,d.creditor_account,d.principal+d.authorized_charges-d.paid pend from plone27_debts d
    where not d.disputed and d.paid<d.principal+d.authorized_charges and d.due_date<=current_date and d.creditor_account is not null order by d.due_date,d.id loop
    continue when not plone27_collectable(r.account_id,r.pend);
    begin perform plone27_debt_pay('auto:debt:'||r.id||':'||r.pend,r.id,r.pend,p_actor); n:=n+1;
    exception when others then insert into plone27_incidents(kind,detail) values('autocobro_fallido',jsonb_build_object('deuda',r.id,'err',sqlerrm)); end;
  end loop; return n; end $$;

-- ========== 7. NÓMINAS (Art. 4.5 cotizaciones, Art. 4.7 SMI, IRP sobre el bruto) ==========
create table if not exists plone27_contracts(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks,
  employer_account uuid not null references plone27_accounts,
  worker_account uuid not null references plone27_accounts,
  worker_user uuid not null,
  gross_monthly numeric(18,2) not null check(gross_monthly>0),
  full_time boolean not null default true check(full_time),          -- jornada parcial: pendiente de norma
  start_date date not null,
  pay_day int not null check(pay_day between 1 and 28),
  next_pay date not null,
  status text not null default 'active' check(status in('active','ended')),
  approved_by uuid not null, created_at timestamptz not null default now());
create table if not exists plone27_payslips(
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references plone27_contracts, pay_date date not null,
  gross numeric(18,2) not null, worker_contrib numeric(18,2) not null, employer_contrib numeric(18,2) not null,
  irp numeric(18,2) not null, net numeric(18,2) not null, tx uuid references plone27_transactions,
  created_at timestamptz not null default now(), unique(contract_id,pay_date));

-- Un contrato no se valida si su bruto semanal equivalente (mensual × 12 / 52) queda por debajo del SMI
create or replace function plone27_contract_guard() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare smi numeric; ek text; wk text; begin
  select kind into ek from plone27_accounts where id=new.employer_account and bank_id=new.bank_id;
  select kind into wk from plone27_accounts where id=new.worker_account and bank_id=new.bank_id;
  if ek is distinct from 'business' then raise exception 'La cuenta empleadora debe ser de empresa de la entidad'; end if;
  if wk is distinct from 'personal' then raise exception 'La cuenta del trabajador debe ser personal de la entidad'; end if;
  smi:=(plone27_setting('smi_semanal_completa_pz',new.bank_id)#>>'{}')::numeric;
  if new.gross_monthly*12/52<smi then raise exception 'Contrato no válido: el bruto está por debajo del SMI (% Pz semanales)',smi; end if;
  return new; end $$;
drop trigger if exists t_contract_guard on plone27_contracts;
drop trigger if exists t_contract_guard on plone27_contracts;
create trigger t_contract_guard before insert or update on plone27_contracts for each row execute function plone27_contract_guard();

create or replace function plone27_contract_create(p_employer uuid,p_worker uuid,p_worker_user uuid,p_gross numeric,p_start date,p_pay_day int,p_approved_by uuid,p_actor uuid)
returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare bk uuid; pd int; first_pay date; cid uuid; begin
  if p_approved_by is null then raise exception 'El contrato exige aprobación registrada'; end if;
  select bank_id into bk from plone27_accounts where id=p_employer; if bk is null then raise exception 'Cuenta empleadora inexistente'; end if;
  pd:=coalesce(p_pay_day,(plone27_setting('dia_nomina',bk)#>>'{}')::int);
  first_pay:=plone27_add_months(p_start,0,pd); if first_pay<p_start then first_pay:=plone27_add_months(p_start,1,pd); end if;
  insert into plone27_contracts(bank_id,employer_account,worker_account,worker_user,gross_monthly,start_date,pay_day,next_pay,approved_by)
    values(bk,p_employer,p_worker,p_worker_user,p_gross,p_start,pd,first_pay,p_approved_by) returning id into cid;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'contract_create','contract',cid::text);
  return cid; end $$;

-- Nómina: empresa paga bruto + cotización empresa; trabajador recibe bruto − cotización trabajador − IRP.
-- Ambas cotizaciones e IRP van a sus cuentas recaudadoras (Cuenta de Reserva por defecto). Cada contrato es aislado.
create or replace function plone27_payroll_run(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c record; v_wt uuid; v_we uuid; v_ir uuid; res uuid; col_irp uuid; wc numeric; ec numeric; ir numeric; lines jsonb; tx uuid; ok int:=0; ko int:=0; begin
  res:=plone27_reserve_account();
  select collector_account into col_irp from plone27_tax_rules where code='IRP';
  for c in select * from plone27_contracts where status='active' and next_pay<=current_date order by next_pay,id loop
    begin
      v_wt:=plone27_active_version('COT_TRA',c.next_pay); v_we:=plone27_active_version('COT_EMP',c.next_pay); v_ir:=plone27_active_version('IRP',c.next_pay);
      if v_wt is null or v_we is null or v_ir is null or col_irp is null then raise exception 'Falta una norma publicada (COT_TRA, COT_EMP o IRP)'; end if;
      wc:=plone27_tax_calc(v_wt,c.gross_monthly); ec:=plone27_tax_calc(v_we,c.gross_monthly); ir:=plone27_tax_calc(v_ir,c.gross_monthly);
      select jsonb_agg(l) into lines from (
        select jsonb_build_object('account',c.employer_account,'dir','debit','amount',c.gross_monthly+ec) l
        union all select jsonb_build_object('account',c.worker_account,'dir','credit','amount',c.gross_monthly-wc-ir)
        union all select jsonb_build_object('account',res,'dir','credit','amount',wc+ec)
        union all select jsonb_build_object('account',col_irp,'dir','credit','amount',ir)) x
        where (l->>'amount')::numeric>0;
      tx:=plone27_post('nomina:'||c.id||':'||c.next_pay,'payroll','Nómina '||to_char(c.next_pay,'YYYY-MM'),lines,p_actor);
      insert into plone27_payslips(contract_id,pay_date,gross,worker_contrib,employer_contrib,irp,net,tx)
        values(c.id,c.next_pay,c.gross_monthly,wc,ec,ir,c.gross_monthly-wc-ir,tx) on conflict(contract_id,pay_date) do nothing;
      update plone27_contracts set next_pay=plone27_add_months(c.next_pay,1,c.pay_day) where id=c.id;
      ok:=ok+1;
    exception when others then
      insert into plone27_incidents(kind,detail) values('nomina_fallida',jsonb_build_object('contrato',c.id,'err',sqlerrm)); ko:=ko+1;
    end;
  end loop;
  return jsonb_build_object('pagadas',ok,'fallidas',ko);
end $$;

-- ========== 8. RBU (Art. 4.6): bono semanal reclamable a mano, caduca, no se acumula, va a una cartera no embargable ==========
create table if not exists plone27_rbu_bonuses(
  id uuid primary key default gen_random_uuid(),
  owner_user uuid not null, wallet_account uuid not null references plone27_accounts,
  week_start date not null, amount numeric(18,2) not null check(amount>0),
  status text not null default 'available' check(status in('available','claimed','expired')),
  expires_on date not null, claimed_at timestamptz, claimed_tx uuid references plone27_transactions,
  unique(owner_user,week_start));

-- Emite el bono de la semana para cada usuario activo. Excluye a menores con control parental (ficha Junior).
create or replace function plone27_rbu_issue_week(p_week date,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u record; wal uuid; bk uuid; n int:=0; amt numeric:=(plone27_setting('rbu_semanal_pz')#>>'{}')::numeric; begin
  for u in select distinct m.user_id from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where a.kind='personal' and a.status='active' and m.role='holder'
      and not exists(select 1 from plone27_customers c join plone27_junior_profiles j on j.customer_id=c.id where c.user_id=m.user_id)
  loop
    continue when exists(select 1 from plone27_rbu_bonuses where owner_user=u.user_id and week_start=p_week);
    select a.bank_id into bk from plone27_accounts a join plone27_account_members m on m.account_id=a.id
      where m.user_id=u.user_id and a.kind='personal' and a.status='active' order by a.created_at limit 1;
    select a.id into wal from plone27_accounts a where a.owner_user=u.user_id and a.kind='personal' and a.name='RBU · cartera';
    if wal is null then
      wal:=(plone27_open_account(bk,'personal','RBU · cartera',u.user_id,p_actor)->>'id')::uuid;
      update plone27_accounts set collectable=false where id=wal;
      insert into plone27_account_members(account_id,user_id,role) values(wal,u.user_id,'holder');
    end if;
    insert into plone27_rbu_bonuses(owner_user,wallet_account,week_start,amount,expires_on) values(u.user_id,wal,p_week,amt,p_week+7);
    n:=n+1;
  end loop; return n; end $$;

create or replace function plone27_rbu_expire(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_rbu_bonuses set status='expired' where status='available' and expires_on<=current_date returning 1)
  select count(*) into n from x; return n; end $$;

-- Reclamación manual por el propio titular. Fondos desde la Cuenta de Reserva (financiada por cotizaciones).
create or replace function plone27_rbu_claim(p_bonus uuid,p_user uuid,p_key text) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b plone27_rbu_bonuses; tx uuid; res uuid; begin
  select * into b from plone27_rbu_bonuses where id=p_bonus for update;
  if b.id is null or b.owner_user is distinct from p_user then raise exception 'Bono no encontrado'; end if;
  if b.status='claimed' then return b.claimed_tx; end if;
  if b.status<>'available' or b.expires_on<=current_date then raise exception 'Bono caducado'; end if;
  res:=plone27_reserve_account();
  if plone27_available(res)<b.amount then raise exception 'Reserva insuficiente para la RBU'; end if;
  tx:=plone27_transfer(p_key,res,b.wallet_account,b.amount,'RBU semanal',p_user);
  update plone27_rbu_bonuses set status='claimed',claimed_at=now(),claimed_tx=tx where id=p_bonus;
  return tx; end $$;

-- ========== 9. INTERÉS DEL CRÉDITO INTERNO: se abona en la cuenta principal de la entidad ==========
create or replace function plone27_accrue_interest(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column declare n int:=0; a record; i numeric; begin
  for a in select ac.id,p.interest_rate r,coalesce(bk.main_account,p.fee_account) fa,b.booked from plone27_accounts ac
    join plone27_products p on p.id=ac.product_id left join plone27_banks bk on bk.id=ac.bank_id join plone27_account_balances b on b.account_id=ac.id
    where p.kind='internal_credit' and p.interest_rate>0 and coalesce(bk.main_account,p.fee_account) is not null and ac.status='active' and b.booked<0 loop
    i:=round(-a.booked*a.r/100/12,2);
    if i>0 then begin perform plone27_post('int:'||a.id||':'||to_char(now(),'YYYY-MM'),'interest','Interés mensual',jsonb_build_array(
        jsonb_build_object('account',a.id,'dir','debit','amount',i),jsonb_build_object('account',a.fa,'dir','credit','amount',i)),p_actor); n:=n+1;
      exception when others then insert into plone27_incidents(kind,detail) values('interest_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end;
    end if;
  end loop; return n; end $$;

-- ========== 10. EJECUCIÓN DIARIA: un paso que falla no bloquea los demás ==========
create or replace function plone27_log_step(p_step text,p_err text) returns void language sql security definer set search_path=public as $$
  insert into plone27_incidents(kind,detail) values('finanzas_diario',jsonb_build_object('paso',p_step,'err',p_err)) $$;

create or replace function plone27_finanzas_daily(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb:='{}'::jsonb; begin
  begin r:=r||jsonb_build_object('rbu_caducados',plone27_rbu_expire(p_actor)); exception when others then perform plone27_log_step('rbu_caducados',sqlerrm); end;
  begin r:=r||jsonb_build_object('rbu_emitidos',plone27_rbu_issue_week(date_trunc('week',current_date)::date,p_actor)); exception when others then perform plone27_log_step('rbu_emitidos',sqlerrm); end;
  begin r:=r||jsonb_build_object('programadas',plone27_run_scheduled(p_actor)); exception when others then perform plone27_log_step('programadas',sqlerrm); end;
  begin r:=r||jsonb_build_object('cuotas_producto',plone27_charge_product_fees(p_actor)); exception when others then perform plone27_log_step('cuotas_producto',sqlerrm); end;
  begin r:=r||jsonb_build_object('interes_credito',plone27_accrue_interest(p_actor)); exception when others then perform plone27_log_step('interes_credito',sqlerrm); end;
  begin r:=r||jsonb_build_object('membresias',plone27_subscriptions_sweep(p_actor)); exception when others then perform plone27_log_step('membresias',sqlerrm); end;
  begin r:=r||jsonb_build_object('nominas',plone27_payroll_run(p_actor)); exception when others then perform plone27_log_step('nominas',sqlerrm); end;
  begin r:=r||jsonb_build_object('planes',plone27_plans_collect(p_actor)); exception when others then perform plone27_log_step('planes',sqlerrm); end;
  begin r:=r||jsonb_build_object('mora',plone27_mora_run(p_actor)); exception when others then perform plone27_log_step('mora',sqlerrm); end;
  begin r:=r||jsonb_build_object('recargos_T57',plone27_apply_late_penalties(p_actor)); exception when others then perform plone27_log_step('recargos_T57',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_recibos',plone27_autocollect_taxes(p_actor)); exception when others then perform plone27_log_step('cobro_recibos',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_deudas',plone27_autocollect_debts(p_actor)); exception when others then perform plone27_log_step('cobro_deudas',sqlerrm); end;
  return r;
end $$;

-- ========== 11. SEGURIDAD: RLS en tablas nuevas, funciones solo para service_role (mismo patrón que 0001–0010) ==========
do $$ declare t text; f text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0012_plone27_certificacion.sql) ====================
-- Placeta One · 0012 · Motor fiscal certificado y prioridad de la normativa T
-- Requiere 0011. Idempotente. Rectifica 0011 donde la prioridad de los Arts. T lo exige.
-- Normativa que lo sustenta: docs/NORMATIVA_MOTOR_FISCAL_CERTIFICADO.md (propuesta pendiente de aprobación).

-- ========== 1. PRIORIDAD DE LOS ARTÍCULOS T ==========
update plone27_settings set value='160' where key='smi_semanal_completa_pz';   -- bruto mínimo semanal: 160 Pz
update plone27_settings set value='false' where key='demora_habilitada';       -- Art. 4.3 (demora por segundo) superado por T57
insert into plone27_settings(key,category,description,vtype,allowed,min_v,max_v,value,sensitive,bank_overridable) values
('capitalia_asume_impuestos_junior','junior','Capitalia paga los impuestos de las operaciones Junior (si es false, paga Placeta Junior). Requiere publicar T105','boolean',null,null,null,'false',true,false)
on conflict(key) do nothing;

-- ========== 2. TRAZABILIDAD DEL RECIBO: obligado y origen de la operación (T20.3, T46) ==========
alter table plone27_tax_receipts add column if not exists obligor_account uuid references plone27_accounts,
  add column if not exists operation_ref text;
create or replace function plone27_receipt_routing() returns trigger language plpgsql as $$
#variable_conflict use_column begin
  new.obligor_account:=nullif(current_setting('plone27.obligor',true),'')::uuid;
  new.operation_ref:=nullif(current_setting('plone27.operacion',true),'');
  return new; end $$;
drop trigger if exists t_receipt_routing on plone27_tax_receipts;
drop trigger if exists t_receipt_routing on plone27_tax_receipts;
create trigger t_receipt_routing before insert on plone27_tax_receipts for each row execute function plone27_receipt_routing();

-- ========== 3. HUELLA DE LA NORMA: la versión publicada queda identificada por su contenido ==========
alter table plone27_tax_rule_versions add column if not exists fingerprint text;
create or replace function plone27_version_fp(p_version uuid) returns text language sql stable as $$
  select encode(sha256(convert_to(coalesce((
    select jsonb_build_object('metodo',v.method,'tasa',v.rate::text,'minimo',v.min_amount::text,'maximo',v.max_amount::text,
      'desde',v.valid_from::text,'hasta',v.valid_to::text,'banco',v.scope_bank,'op',v.scope_op,
      'tramos',(select coalesce(jsonb_agg(jsonb_build_object('d',b.from_amount::text,'h',b.to_amount::text,'t',b.rate::text) order by b.from_amount),'[]'::jsonb)
                from plone27_tax_brackets b where b.version_id=v.id))::text
    from plone27_tax_rule_versions v where v.id=p_version),''),'utf8')),'hex') $$;

-- Publicar sella la huella en la misma operación (la versión queda inmutable por rv_guard)
create or replace function plone27_tax_publish(p_version uuid,p_approver uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v plone27_tax_rule_versions; begin
  select * into v from plone27_tax_rule_versions where id=p_version for update;
  if v.id is null or v.status<>'draft' then raise exception 'La versión no está en borrador'; end if;
  if p_approver is null or p_approver is not distinct from v.author then raise exception 'Publicar exige un aprobador distinto del autor'; end if;
  update plone27_tax_rule_versions set status='published',approver=p_approver,published_at=now(),fingerprint=plone27_version_fp(p_version) where id=p_version;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_publish','tax_version',p_version::text,jsonb_build_object('approver',p_approver));
end $$;

-- Tramos inmutables una vez publicada la versión (las evaluaciones también son de solo añadir)
create or replace function plone27_bracket_guard() returns trigger language plpgsql as $$
#variable_conflict use_column
declare vid uuid; begin
  vid:=case when tg_op='DELETE' then old.version_id else new.version_id end;
  if exists(select 1 from plone27_tax_rule_versions v where v.id=vid and v.status='published') then raise exception 'Tramos de una versión publicada: inmutables'; end if;
  if tg_op='DELETE' then return old; end if; return new; end $$;
drop trigger if exists t_bracket_guard on plone27_tax_brackets;
drop trigger if exists t_bracket_guard on plone27_tax_brackets;
create trigger t_bracket_guard before insert or update or delete on plone27_tax_brackets for each row execute function plone27_bracket_guard();
drop trigger if exists t_eval_ro on plone27_tax_evaluations;
drop trigger if exists t_eval_ro on plone27_tax_evaluations;
create trigger t_eval_ro before update or delete on plone27_tax_evaluations for each row execute function plone27_immutable();

-- ========== 4. DESGLOSE DEL CÁLCULO: cada tramo con su base e importe, sin redondear hasta el final (igual que plone27_tax_calc) ==========
create or replace function plone27_tax_trace(p_version uuid,p_base numeric) returns jsonb language plpgsql stable as $$
#variable_conflict use_column
declare v plone27_tax_rule_versions; res jsonb:='[]'::jsonb; b record; part numeric; begin
  select * into v from plone27_tax_rule_versions where id=p_version;
  if v.id is null then return null; end if;
  if v.method='percent' then return jsonb_build_array(jsonb_build_object('metodo','percent','tasa',v.rate::text,'base',p_base::text)); end if;
  if v.method='fixed' then return jsonb_build_array(jsonb_build_object('metodo','fixed','importe',v.rate::text)); end if;
  for b in select * from plone27_tax_brackets where version_id=p_version order by from_amount loop
    if v.method='brackets' and p_base>b.from_amount then part:=least(p_base,coalesce(b.to_amount,p_base))-b.from_amount;
    elsif v.method='bracket_flat' and p_base>b.from_amount and (b.to_amount is null or p_base<=b.to_amount) then part:=p_base;
    else continue; end if;
    res:=res||jsonb_build_object('desde',b.from_amount::text,'hasta',b.to_amount::text,'tasa',b.rate::text,'base_tramo',part::text,'importe',(part*b.rate/100)::text);
  end loop;
  return res; end $$;

-- ========== 5. CERTIFICADOS: cadena de huellas, de solo añadir ==========
create table if not exists plone27_tax_certificates(
  seq bigint generated always as identity primary key,
  id uuid not null unique default gen_random_uuid(),
  kind text not null check(kind in('recibo','regularizacion','recargo')),
  subject_id uuid not null, version_id uuid references plone27_tax_rule_versions, fingerprint text,
  base numeric(18,2) not null, amount numeric(18,2) not null, inputs jsonb not null,
  prev_hash text not null, hash text not null unique, created_at timestamptz not null default now(),
  unique(kind,subject_id));
drop trigger if exists t_cert_ro on plone27_tax_certificates;
drop trigger if exists t_cert_ro on plone27_tax_certificates;
create trigger t_cert_ro before update or delete on plone27_tax_certificates for each row execute function plone27_immutable();

-- Texto canónico que se hashea. Verificación y emisión usan esta misma función: el formato no puede divergir.
create or replace function plone27_cert_text(p_prev text,p_kind text,p_subject uuid,p_version uuid,p_fp text,p_base text,p_amount text,p_inputs jsonb) returns text
language sql immutable as $$ select p_prev||'|'||p_kind||'|'||p_subject::text||'|'||coalesce(p_version::text,'-')||'|'||coalesce(p_fp,'-')||'|'||p_base||'|'||p_amount||'|'||p_inputs::text $$;

create or replace function plone27_cert_append(p_kind text,p_subject uuid,p_version uuid,p_base numeric,p_amount numeric,p_inputs jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare prev text; fp text; bt text:=p_base::numeric(18,2)::text; am text:=p_amount::numeric(18,2)::text; h text; cid uuid; begin
  perform pg_advisory_xact_lock(hashtext('plone27_cert'));
  select hash into prev from plone27_tax_certificates order by seq desc limit 1; prev:=coalesce(prev,'GENESIS');
  fp:=(select fingerprint from plone27_tax_rule_versions where id=p_version);
  h:=encode(sha256(convert_to(plone27_cert_text(prev,p_kind,p_subject,p_version,fp,bt,am,p_inputs),'utf8')),'hex');
  insert into plone27_tax_certificates(kind,subject_id,version_id,fingerprint,base,amount,inputs,prev_hash,hash)
    values(p_kind,p_subject,p_version,fp,p_base,p_amount,p_inputs,prev,h) returning id into cid;
  return cid; end $$;

-- Todo recibo se certifica al nacer. Si el importe no coincide con la norma (regularización o ajuste), se marca como tal.
create or replace function plone27_cert_receipt() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare kind text; begin
  kind:=case when new.amount=plone27_tax_calc(new.rule_version_id,new.base) then 'recibo' else 'regularizacion' end;
  perform plone27_cert_append(kind,new.id,new.rule_version_id,new.base,new.amount,
    jsonb_build_object('tramos',plone27_tax_trace(new.rule_version_id,new.base),'cuenta',new.account_id,'obligado',new.obligor_account,'operacion',new.operation_ref));
  return null; end $$;
drop trigger if exists t_cert_receipt on plone27_tax_receipts;
drop trigger if exists t_cert_receipt on plone27_tax_receipts;
create trigger t_cert_receipt after insert on plone27_tax_receipts for each row execute function plone27_cert_receipt();

-- Certificado de un recibo para mostrar en web y app (sin datos de seguridad; solo cálculo y huella)
create or replace function plone27_receipt_certificate(p_receipt uuid) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('recibo',r.ref,'norma',ru.code,'version',v.version,'huella_norma',c.fingerprint,'base',c.base,'importe',c.amount,
    'calculo',c.inputs,'seq',c.seq,'hash',c.hash,'hash_anterior',c.prev_hash,'emitido',c.created_at)
  from plone27_tax_certificates c join plone27_tax_receipts r on r.id=c.subject_id
    join plone27_tax_rule_versions v on v.id=c.version_id join plone27_tax_rules ru on ru.id=v.rule_id
  where c.kind in('recibo','regularizacion') and c.subject_id=p_receipt $$;

-- Informe de veracidad: recalcula toda la cadena y cada importe con la norma vigente
create or replace function plone27_certification_report() returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare c record; prev text:='GENESIS'; h text; total int:=0; rota int:=0; disc int:=0; alterados int; reg int:=0; fpd int; sin int; begin
  for c in select * from plone27_tax_certificates order by seq loop
    total:=total+1;
    if c.prev_hash<>prev then rota:=rota+1; end if;
    h:=encode(sha256(convert_to(plone27_cert_text(c.prev_hash,c.kind,c.subject_id,c.version_id,c.fingerprint,c.base::text,c.amount::text,c.inputs),'utf8')),'hex');
    if h<>c.hash then rota:=rota+1; end if;
    prev:=c.hash;
    if c.kind='recibo' then
      if plone27_tax_calc(c.version_id,c.base)<>c.amount then disc:=disc+1; end if;
    elsif c.kind='recargo' then
      if round(c.base*(c.inputs->>'tramo')::numeric/100,2)-(c.inputs->>'cobrado_previo')::numeric<>c.amount then disc:=disc+1; end if;
    else reg:=reg+1; end if;
  end loop;
  select count(*) into fpd from plone27_tax_rule_versions v where v.status='published' and v.fingerprint is distinct from plone27_version_fp(v.id);
  select count(*) into alterados from plone27_tax_receipts r join plone27_tax_certificates c on c.kind in('recibo','regularizacion') and c.subject_id=r.id
    where r.amount<>c.amount or r.base<>c.base;
  select count(*) into sin from plone27_tax_receipts r where not exists(select 1 from plone27_tax_certificates c where c.kind in('recibo','regularizacion') and c.subject_id=r.id);
  return jsonb_build_object('certificados',total,'cadena_rota',rota,'importes_no_recalculan',disc,'importes_alterados_tras_emision',alterados,
    'huella_norma_discrepante',fpd,'recibos_sin_certificado',sin,'regularizaciones_informativas',reg,
    'estado',case when rota+disc+alterados+fpd+sin=0 then 'OK' else 'REVISAR' end);
end $$;

-- ========== 6. PAGADOR JUNIOR (Capitalia) ==========
create or replace function plone27_set_junior_payer(p_bank uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if not exists(select 1 from plone27_banks where id=p_bank and main_account is not null) then raise exception 'La entidad necesita cuenta principal'; end if;
  insert into plone27_config(key,value) values('entidad_capitalia',p_bank::text) on conflict(key) do update set value=excluded.value;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'junior_payer','bank',p_bank::text);
end $$;

create or replace function plone27_junior_tax_payer() returns uuid language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  if (plone27_setting('capitalia_asume_impuestos_junior')#>>'{}')::boolean then
    select bk.main_account into acc from plone27_config c join plone27_banks bk on bk.id=nullif(c.value,'')::uuid where c.key='entidad_capitalia';
    if acc is null then raise exception 'Capitalia no tiene cuenta principal configurada'; end if;
  else
    select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_placeta_junior';
    if acc is null then raise exception 'Falta la cuenta de Placeta Junior (seed 0011)'; end if;
  end if;
  return acc; end $$;

-- Impuesto de una operación Junior: el obligado queda registrado (el usuario Junior) y el pago sale de la cuenta pagadora
create or replace function plone27_tax_issue_junior(p_code text,p_junior uuid,p_base numeric,p_event_key text,p_op text,p_pathway text,p_due date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare payer uuid; rid uuid; begin
  if (select kind from plone27_accounts where id=p_junior) is distinct from 'junior' then raise exception 'La cuenta no es Junior'; end if;
  payer:=plone27_junior_tax_payer();
  perform set_config('plone27.obligor',p_junior::text,true);
  perform set_config('plone27.operacion',p_event_key,true);
  rid:=plone27_tax_issue(p_code,payer,p_base,p_event_key,p_op,p_pathway,p_due,p_actor);
  perform set_config('plone27.obligor','',true); perform set_config('plone27.operacion','',true);
  return rid; end $$;

-- ========== 7. OPERACIONES SUJETAS: venta con IVA desglosado (Art. 4.4 y T26–T28) ==========
create or replace function plone27_sale(p_key text,p_buyer uuid,p_seller uuid,p_base numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare vid uuid; iva numeric:=0; tx uuid; rid uuid; due date:=current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int; begin
  if p_base<=0 then raise exception 'Base de venta no válida'; end if;
  vid:=plone27_active_version('IVA',current_date);
  if vid is null then raise exception 'No hay norma de IVA publicada'; end if;
  if not exists(select 1 from plone27_tax_exemptions e join plone27_tax_rules ru on ru.id=e.rule_id
                where ru.code='IVA' and e.account_id=p_seller and current_date>=e.valid_from and (e.valid_to is null or current_date<=e.valid_to)) then
    iva:=plone27_tax_calc(vid,p_base);
  end if;
  tx:=plone27_transfer(p_key,p_buyer,p_seller,p_base+iva,'Venta · base '||p_base::text||' · IVA '||iva::text,p_actor);
  if iva>0 then
    if (select kind from plone27_accounts where id=p_buyer)='junior' then
      rid:=plone27_tax_issue_junior('IVA',p_buyer,p_base,'iva:'||p_key,null,'automatica',due,p_actor);
    else
      rid:=plone27_tax_issue('IVA',p_seller,p_base,'iva:'||p_key,null,'automatica',due,p_actor);
    end if;
  end if;
  return tx; end $$;

-- ========== 8. BASES DECLARADAS (IRM, IBA, IGF, IPE, ITP): el cálculo es automático, la base la declara alguien y la aprueba otra persona ==========
create or replace function plone27_tax_declare(p_code text,p_account uuid,p_periodo text,p_base numeric,p_declarante uuid,p_aprobador uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rid uuid; due date:=current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int; begin
  if p_aprobador is null or p_aprobador is not distinct from p_declarante then raise exception 'La declaración exige la aprobación de otra persona'; end if;
  if (select kind from plone27_accounts where id=p_account)='junior' then
    rid:=plone27_tax_issue_junior(p_code,p_account,p_base,'decl:'||p_code||':'||p_account||':'||p_periodo,null,'declaracion',due,p_actor);
  else
    perform set_config('plone27.operacion','declaracion:'||p_periodo||':aprobada_por:'||p_aprobador::text,true);
    rid:=plone27_tax_issue(p_code,p_account,p_base,'decl:'||p_code||':'||p_account||':'||p_periodo,null,'declaracion',due,p_actor);
    perform set_config('plone27.operacion','',true);
  end if;
  return rid; end $$;

-- ========== 9. ACTIVIDADES Y IAEP MENSUAL (Art. T41–T43): cuota fija por categoría, automática cada mes ==========
create table if not exists plone27_activities(id uuid primary key default gen_random_uuid(), account_id uuid not null references plone27_accounts,
  category text not null check(category in('microactividad','pequena','mediana','grande','especial')),
  registered_at date not null default current_date, status text not null default 'active' check(status in('active','closed')),
  created_at timestamptz not null default now());

create or replace function plone27_activity_register(p_account uuid,p_category text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare aid uuid; begin
  if not exists(select 1 from plone27_accounts where id=p_account and kind in('business','personal') and status='active') then raise exception 'La actividad requiere una cuenta activa'; end if;
  insert into plone27_activities(account_id,category) values(p_account,p_category) returning id into aid;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'activity_register','activity',aid::text); return aid; end $$;

create or replace function plone27_iaep_monthly(p_period date,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare a record; vid uuid; amt numeric; rid uuid; n int:=0; begin
  for a in select * from plone27_activities where status='active' and registered_at<=p_period loop
    select ver.id into vid from plone27_tax_rule_versions ver join plone27_tax_rules ru on ru.id=ver.rule_id
      where ru.code='IAEP' and ver.scope_op=a.category and ver.status='published' and p_period>=ver.valid_from and (ver.valid_to is null or p_period<=ver.valid_to) limit 1;
    if vid is null then insert into plone27_incidents(kind,detail) values('iaep_sin_norma',jsonb_build_object('actividad',a.id)); continue; end if;
    amt:=plone27_tax_calc(vid,0);
    continue when amt<=0;   -- microactividad: cuota cero, sin recibo (Art. T43.2)
    rid:=plone27_tax_issue('IAEP',a.account_id,0,'iaep:'||a.id||':'||to_char(p_period,'YYYY-MM'),a.category,'periodica',
                           p_period+(plone27_setting('default_receipt_due_days')#>>'{}')::int,p_actor);
    if rid is not null then n:=n+1; end if;
  end loop; return n; end $$;

-- ========== 10. RECARGOS T57 (prevalecen sobre el Art. 4.3): tramo por días de retraso, sobre lo pendiente ==========
create or replace function plone27_bracket_rate(p_version uuid,p_value numeric) returns numeric language sql stable as $$
  select b.rate from plone27_tax_brackets b where b.version_id=p_version and p_value>b.from_amount and (b.to_amount is null or p_value<=b.to_amount) limit 1 $$;

-- Recargo = pendiente × tipo del tramo vigente − lo ya recargado. Solo cambia si sube el tramo. Nunca se devuelve si baja.
create or replace function plone27_t57_run(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; vid uuid; rate numeric; dias int; target numeric; previo numeric; diff numeric; did uuid; n int:=0; begin
  vid:=plone27_active_version('RECARGO_T57',current_date);
  if vid is null then return 0; end if;   -- sin norma T57 publicada no hace nada
  for r in select t.id,t.account_id,t.due_date,t.amount-t.paid_amount pend,ru.collector_account col,ver.approver apr
    from plone27_tax_receipts t join plone27_tax_rule_versions ver on ver.id=t.rule_version_id join plone27_tax_rules ru on ru.id=ver.rule_id
    where t.status in('issued','partial') and not t.disputed and t.original_receipt is null and t.due_date<current_date loop
    dias:=current_date-r.due_date;
    rate:=coalesce(plone27_bracket_rate(vid,dias),0);
    target:=round(r.pend*rate/100,2);
    select coalesce(sum(principal),0) into previo from plone27_debts where origin like 'T57:'||r.id::text||':%';
    diff:=target-previo;
    continue when diff<0.01;
    insert into plone27_debts(account_id,creditor_account,principal,due_date,reason,authorized_by,origin)
      values(r.account_id,r.col,diff,current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int,
             'Recargo T57 (tramo '||rate::text||' %) sobre recibo',r.apr,'T57:'||r.id::text||':'||rate::text||':'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSUS'))
      returning id into did;
    perform plone27_cert_append('recargo',did,vid,r.pend,diff,jsonb_build_object('tramo',rate,'dias',dias,'objetivo',target,'cobrado_previo',previo,'recibo',r.id));
    n:=n+1;
  end loop; return n; end $$;

-- ========== 11. AUTOCOBRO: sin importes a cero (un cobro de 0 Pz no es un cobro) ==========
create or replace function plone27_autocollect_taxes(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; n int:=0; begin
  if not (plone27_setting('autocobro_habilitado'))::boolean then return 0; end if;
  for r in select t.id,t.account_id,t.amount-t.paid_amount pend from plone27_tax_receipts t
    where t.status in('issued','partial') and not t.disputed and t.due_date<=current_date and t.amount-t.paid_amount>0 order by t.due_date,t.id loop
    continue when not plone27_collectable(r.account_id,r.pend);
    begin perform plone27_tax_pay_partial('auto:tax:'||r.id||':'||r.pend,r.id,r.pend,p_actor); n:=n+1;
    exception when others then insert into plone27_incidents(kind,detail) values('autocobro_fallido',jsonb_build_object('recibo',r.id,'err',sqlerrm)); end;
  end loop; return n; end $$;

-- ========== 12. EJECUCIÓN DIARIA (sustituye la de 0011): recargos T57, IAEP, certificación ==========
create or replace function plone27_finanzas_daily(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb:='{}'::jsonb; begin
  begin r:=r||jsonb_build_object('rbu_caducados',plone27_rbu_expire(p_actor)); exception when others then perform plone27_log_step('rbu_caducados',sqlerrm); end;
  begin r:=r||jsonb_build_object('rbu_emitidos',plone27_rbu_issue_week(date_trunc('week',current_date)::date,p_actor)); exception when others then perform plone27_log_step('rbu_emitidos',sqlerrm); end;
  begin r:=r||jsonb_build_object('programadas',plone27_run_scheduled(p_actor)); exception when others then perform plone27_log_step('programadas',sqlerrm); end;
  begin r:=r||jsonb_build_object('cuotas_producto',plone27_charge_product_fees(p_actor)); exception when others then perform plone27_log_step('cuotas_producto',sqlerrm); end;
  begin r:=r||jsonb_build_object('interes_credito',plone27_accrue_interest(p_actor)); exception when others then perform plone27_log_step('interes_credito',sqlerrm); end;
  begin r:=r||jsonb_build_object('membresias',plone27_subscriptions_sweep(p_actor)); exception when others then perform plone27_log_step('membresias',sqlerrm); end;
  begin r:=r||jsonb_build_object('nominas',plone27_payroll_run(p_actor)); exception when others then perform plone27_log_step('nominas',sqlerrm); end;
  begin r:=r||jsonb_build_object('planes',plone27_plans_collect(p_actor)); exception when others then perform plone27_log_step('planes',sqlerrm); end;
  begin r:=r||jsonb_build_object('iaep',plone27_iaep_monthly(current_date,p_actor)); exception when others then perform plone27_log_step('iaep',sqlerrm); end;
  begin r:=r||jsonb_build_object('mora',plone27_mora_run(p_actor)); exception when others then perform plone27_log_step('mora',sqlerrm); end;
  begin r:=r||jsonb_build_object('recargos_T57',plone27_t57_run(p_actor)); exception when others then perform plone27_log_step('recargos_T57',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_recibos',plone27_autocollect_taxes(p_actor)); exception when others then perform plone27_log_step('cobro_recibos',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_deudas',plone27_autocollect_debts(p_actor)); exception when others then perform plone27_log_step('cobro_deudas',sqlerrm); end;
  begin r:=r||jsonb_build_object('certificacion',plone27_certification_report());
    if r->'certificacion'->>'estado'<>'OK' then insert into plone27_incidents(kind,detail) values('certificacion',r->'certificacion'); end if;
  exception when others then perform plone27_log_step('certificacion',sqlerrm); end;
  return r;
end $$;

-- ========== 13. SEGURIDAD (mismo patrón que 0001–0011) ==========
do $$ declare t text; f text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0013_plone27_iva_cuentas.sql) ====================
-- Placeta One · 0013 · Cuentas con IBAN para tributos y RBU, destinos por impuesto, cuentas institucionales
-- para operar con Junior, IVA de ventas con detección y regularización, y certificados que se rectifican
-- emitiendo otro certificado (el primero nunca se modifica). Requiere 0012. Idempotente.

-- ========== 1. AJUSTES ==========
insert into plone27_settings(key,category,description,vtype,allowed,min_v,max_v,value,sensitive,bank_overridable) values
('smi_mensual_completa_pz','laboral','SMI mensual para jornada completa (Pz). Instrucción de la Junta: 160 Pz al mes','number',null,0,100000,'160',true,false),
('iva_criterio','fiscalidad','Lectura del importe de una operación sin IVA desglosado: exclusivo = el importe es la base; inclusivo = el importe ya incluye el IVA','enum','{exclusivo,inclusivo}',null,null,'"exclusivo"',true,false),
('iva_umbral_fraccionamiento','fiscalidad','Importe (Pz) a partir del cual varias transferencias pequeñas al mismo comercio en un día son fraccionamiento','number',null,0,1000000,'500',true,false),
('iva_patron_pagadores','fiscalidad','Nº de pagadores distintos a partir del cual una cuenta personal se revisa como posible comercio','number',null,1,1000,'5',true,false),
('iva_ventana_patron_dias','fiscalidad','Días de la ventana del patrón comercial en cuentas personales','number',null,1,365,'30',true,false)
on conflict(key) do nothing;
update plone27_settings set value='36.92', description='Equivalente semanal informativo del SMI mensual (no valida contratos)' where key='smi_semanal_completa_pz';
update plone27_settings set value='true' where key='capitalia_asume_impuestos_junior';
do $$ begin if not exists(select 1 from plone27_audit_log where action='decision' and entity_id='capitalia_asume_impuestos_junior') then
insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(null,'decision','setting','capitalia_asume_impuestos_junior',
  jsonb_build_object('valor',true,'texto','Capitalia paga en nombre de los usuarios Junior los impuestos mensuales y cualquier otro. El obligado sigue siendo el usuario Junior.'));
end if; end $$;

-- ========== 2. CUENTAS INSTITUCIONALES (las que pueden operar con Junior y las que reciben tributos) ==========
create table if not exists plone27_institutional_accounts(
  account_id uuid primary key references plone27_accounts,
  motivo text not null check(length(motivo)>=10),
  puede_operar_junior boolean not null default false,
  aprobado_por uuid,                                  -- null = pendiente de registrar aprobador (ver seed)
  created_at timestamptz not null default now());

create or replace function plone27_es_institucional(p_acc uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_accounts a join plone27_banks b on b.id=a.bank_id where a.id=p_acc and b.code='0000')
      or exists(select 1 from plone27_banks b where b.main_account=p_acc or b.tax_account=p_acc)
      or exists(select 1 from plone27_institutional_accounts i where i.account_id=p_acc) $$;

create or replace function plone27_institutional_set(p_account uuid,p_motivo text,p_junior boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  if not exists(select 1 from plone27_accounts where id=p_account) then raise exception 'Cuenta inexistente'; end if;
  insert into plone27_institutional_accounts(account_id,motivo,puede_operar_junior,aprobado_por) values(p_account,p_motivo,coalesce(p_junior,false),p_actor)
    on conflict(account_id) do update set motivo=excluded.motivo,puede_operar_junior=excluded.puede_operar_junior,aprobado_por=excluded.aprobado_por;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'institutional_set','account',p_account::text,jsonb_build_object('junior',p_junior,'motivo',p_motivo));
end $$;

-- Junior: solo las cuentas institucionales marcadas pueden operar con cuentas Junior (junior con junior sigue igual)
create or replace function plone27_junior_counterparty() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if exists(select 1 from (select distinct n.transaction_id from new_rows n join plone27_transactions t on t.id=n.transaction_id where t.kind<>'reversal') x
    where exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind='junior')
      and exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
                 where e.transaction_id=x.transaction_id and a.kind in('personal','shared','business')
                   and not exists(select 1 from plone27_institutional_accounts i where i.account_id=a.id and i.puede_operar_junior)))
  then raise exception 'Cuenta Junior: no puede enviar ni recibir de cuentas de clientes habituales'; end if;
  return null; end $$;

-- Destinos de cada impuesto: solo cuentas institucionales
create or replace function plone27_tax_set_destination(p_code text,p_account uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare old uuid; begin
  if not plone27_es_institucional(p_account) then raise exception 'El destino debe ser una cuenta institucional'; end if;
  select collector_account into old from plone27_tax_rules where code=p_code;
  if not found then raise exception 'Impuesto desconocido: %',p_code; end if;
  update plone27_tax_rules set collector_account=p_account where code=p_code;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_destination','tax_rule',p_code,jsonb_build_object('anterior',old,'nuevo',p_account));
end $$;

-- Cuentas de configuración (IBAN de tributos y origen de la RBU). Solo institucionales.
create or replace function plone27_config_set(p_key text,p_account uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if p_key not in('cuenta_tributos','cuenta_rbu_origen') then raise exception 'Clave no permitida: %',p_key; end if;
  if not plone27_es_institucional(p_account) then raise exception 'La cuenta debe ser institucional'; end if;
  insert into plone27_config(key,value) values(p_key,p_account::text) on conflict(key) do update set value=excluded.value;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'config_set','config',p_key,jsonb_build_object('cuenta',p_account));
end $$;

-- ========== 3. VENTAS, IVA Y HALLAZGOS ==========
create table if not exists plone27_sales(
  tx uuid primary key references plone27_transactions,
  seller_account uuid not null references plone27_accounts, buyer_account uuid references plone27_accounts,
  base numeric(18,2) not null, iva numeric(18,2),
  origin text not null check(origin in('plataforma','regularizada')),
  created_at timestamptz not null default now());

create table if not exists plone27_iva_findings(
  id uuid primary key default gen_random_uuid(),
  ref_key text not null unique,
  kind text not null check(kind in('cobro_comercial_sin_iva','patron_comercial_personal','fraccionamiento')),
  tx uuid references plone27_transactions,
  account_id uuid not null references plone27_accounts,          -- receptor
  counterpart_account uuid references plone27_accounts,          -- pagador
  amount numeric(18,2) not null, iva_due numeric(18,2),
  severity text not null check(severity in('alta','media','baja')),
  status text not null default 'abierto' check(status in('abierto','regularizado','descartado')),
  propuesta_accion text check(propuesta_accion in('regularizar','descartar')),
  propuesto_por uuid, motivo text, aprobado_por uuid,
  receipt_id uuid references plone27_tax_receipts,
  detected_at timestamptz not null default now(), resolved_at timestamptz);

-- IVA sobre un importe total: devuelve base e IVA según el criterio configurado. Sin norma vigente: IVA null.
create or replace function plone27_iva_split(p_total numeric) returns table(base numeric, iva numeric) language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare vid uuid; tasa numeric; begin
  vid:=plone27_active_version('IVA',current_date);
  if vid is null then base:=p_total; iva:=null; return next; return; end if;
  select rate into tasa from plone27_tax_rule_versions where id=vid;
  if (plone27_setting('iva_criterio')#>>'{}')='inclusivo' then base:=round(p_total*100/(100+tasa),2); iva:=p_total-base;
  else base:=p_total; iva:=plone27_tax_calc(vid,p_total); end if;
  return next; end $$;

-- Venta de la plataforma: el comprador paga base + IVA y el vendedor liquida el IVA. Queda registrada como venta.
create or replace function plone27_sale(p_key text,p_buyer uuid,p_seller uuid,p_base numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare vid uuid; iva numeric:=0; tx uuid; rid uuid; due date:=current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int; begin
  if p_base<=0 then raise exception 'Base de venta no válida'; end if;
  vid:=plone27_active_version('IVA',current_date);
  if vid is null then raise exception 'No hay norma de IVA publicada'; end if;
  if not exists(select 1 from plone27_tax_exemptions e join plone27_tax_rules ru on ru.id=e.rule_id
                where ru.code='IVA' and e.account_id=p_seller and current_date>=e.valid_from and (e.valid_to is null or current_date<=e.valid_to)) then
    iva:=plone27_tax_calc(vid,p_base);
  end if;
  tx:=plone27_transfer(p_key,p_buyer,p_seller,p_base+iva,'Venta · base '||p_base::text||' · IVA '||iva::text,p_actor);
  insert into plone27_sales(tx,seller_account,buyer_account,base,iva,origin) values(tx,p_seller,p_buyer,p_base,iva,'plataforma');
  if iva>0 then
    if (select kind from plone27_accounts where id=p_buyer)='junior' then
      rid:=plone27_tax_issue_junior('IVA',p_buyer,p_base,'iva:'||p_key,null,'automatica',due,p_actor);
    else
      rid:=plone27_tax_issue('IVA',p_seller,p_base,'iva:'||p_key,null,'automatica',due,p_actor);
    end if;
  end if;
  return tx; end $$;

-- Detección: cobros comerciales sin venta registrada, patrones de comercio en cuentas personales y fraccionamiento.
-- Idempotente: cada hallazgo tiene una clave única. No cambia dinero: solo registra.
create or replace function plone27_iva_scan(p_desde timestamptz,p_hasta timestamptz,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rr record; sp record; n1 int:=0; n3 int:=0; n4 int:=0; umbral numeric; patron int; ventana int; ivad numeric; sev text; begin
  umbral:=(plone27_setting('iva_umbral_fraccionamiento')#>>'{}')::numeric;
  patron:=(plone27_setting('iva_patron_pagadores')#>>'{}')::int;
  ventana:=(plone27_setting('iva_ventana_patron_dias')#>>'{}')::int;
  -- R1: transferencia que entra en una cuenta comercial y no está registrada como venta
  for rr in
    select tx.id tx_id, c.account_id receptor, c.total, (array_agg(d.account_id))[1] pagador
    from plone27_transactions tx
    join lateral (select e.account_id, sum(e.amount) total from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
                  where e.transaction_id=tx.id and e.direction='credit' and a.kind='business' group by e.account_id) c on true
    join plone27_ledger_entries d on d.transaction_id=tx.id and d.direction='debit'
    where tx.kind='transfer' and tx.status='posted' and tx.created_at>=p_desde and tx.created_at<p_hasta
      and not exists(select 1 from plone27_sales sl where sl.tx=tx.id)
      and not plone27_es_institucional(c.account_id)
    group by tx.id, c.account_id, c.total
  loop
    select iva into ivad from plone27_iva_split(rr.total);
    sev:=case when rr.total>=1000 then 'alta' when rr.total>=100 then 'media' else 'baja' end;
    insert into plone27_iva_findings(ref_key,kind,tx,account_id,counterpart_account,amount,iva_due,severity)
      values('tx:'||rr.tx_id::text,'cobro_comercial_sin_iva',rr.tx_id,rr.receptor,rr.pagador,rr.total,ivad,sev)
      on conflict(ref_key) do nothing;
    if found then n1:=n1+1; end if;
  end loop;
  -- R3: cuenta personal que recibe de muchos pagadores distintos (patrón de comercio)
  for sp in
    select r.account_id receptor, count(distinct d.account_id) n_pagadores, sum(r.amount) total
    from plone27_ledger_entries r
    join plone27_accounts ar on ar.id=r.account_id and ar.kind='personal'
    join plone27_transactions tx on tx.id=r.transaction_id and tx.kind='transfer' and tx.status='posted'
    join plone27_ledger_entries d on d.transaction_id=tx.id and d.direction='debit' and d.account_id<>r.account_id
    where r.direction='credit' and tx.created_at>=now()-make_interval(days=>ventana) and not plone27_es_institucional(d.account_id)
    group by r.account_id
    having count(distinct d.account_id)>=patron
  loop
    insert into plone27_iva_findings(ref_key,kind,account_id,amount,severity)
      values('patron:'||sp.receptor::text||':'||current_date::text,'patron_comercial_personal',sp.receptor,sp.total,'media')
      on conflict(ref_key) do nothing;
    if found then n3:=n3+1; end if;
  end loop;
  -- R4: fraccionamiento: varias transferencias pequeñas del mismo pagador al mismo comercio en un día
  for sp in
    select d.account_id pagador, r.account_id receptor, count(*) n, sum(r.amount) total
    from plone27_ledger_entries r
    join plone27_accounts ar on ar.id=r.account_id and ar.kind='business'
    join plone27_transactions tx on tx.id=r.transaction_id and tx.kind='transfer' and tx.status='posted'
    join plone27_ledger_entries d on d.transaction_id=tx.id and d.direction='debit' and d.account_id<>r.account_id
    where r.direction='credit' and r.amount<umbral and tx.created_at>=now()-interval '1 day'
      and not plone27_es_institucional(r.account_id) and not plone27_es_institucional(d.account_id)
    group by d.account_id, r.account_id
    having count(*)>=2 and sum(r.amount)>=umbral
  loop
    select iva into ivad from plone27_iva_split(sp.total);
    insert into plone27_iva_findings(ref_key,kind,account_id,counterpart_account,amount,iva_due,severity)
      values('frac:'||sp.receptor::text||':'||sp.pagador::text||':'||current_date::text,'fraccionamiento',sp.receptor,sp.pagador,sp.total,ivad,'alta')
      on conflict(ref_key) do nothing;
    if found then n4:=n4+1; end if;
  end loop;
  return jsonb_build_object('cobros_sin_iva',n1,'patrones_personales',n3,'fraccionamientos',n4);
end $$;

-- Regla de cuatro ojos: quien propone no aprueba. Solo se propone «regularizar» o «descartar».
create or replace function plone27_iva_propose(p_finding uuid,p_accion text,p_motivo text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if p_accion not in('regularizar','descartar') then raise exception 'Acción no válida'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  update plone27_iva_findings set propuesta_accion=p_accion,motivo=p_motivo,propuesto_por=p_actor where id=p_finding and status='abierto';
  if not found then raise exception 'Hallazgo no abierto'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_propose','finding',p_finding::text,jsonb_build_object('accion',p_accion,'motivo',p_motivo));
end $$;

create or replace function plone27_iva_approve(p_finding uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f plone27_iva_findings; base_ numeric; iva_ numeric; rid uuid; due date:=current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int; begin
  select * into f from plone27_iva_findings where id=p_finding for update;
  if f.id is null or f.status<>'abierto' then raise exception 'Hallazgo no abierto'; end if;
  if f.propuesta_accion is null then raise exception 'Falta una propuesta de regularización'; end if;
  if f.propuesto_por is not distinct from p_actor then raise exception 'Quien propone no puede aprobar'; end if;
  if f.propuesta_accion='descartar' then
    update plone27_iva_findings set status='descartado',aprobado_por=p_actor,resolved_at=now() where id=p_finding;
    insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'iva_discard','finding',p_finding::text);
    return null;
  end if;
  if f.kind<>'cobro_comercial_sin_iva' then raise exception 'Solo se regulariza un cobro comercial sin IVA'; end if;
  select s.base,s.iva into base_,iva_ from plone27_iva_split(f.amount) s;
  if base_ is null or iva_ is null then raise exception 'No hay norma de IVA vigente para regularizar'; end if;
  rid:=plone27_tax_issue('IVA',f.account_id,base_,'iva-reg:'||f.id::text,null,'regularizacion',due,p_actor);
  if rid is null then raise exception 'La regularización no genera recibo (exención o norma en conflicto)'; end if;
  select amount into iva_ from plone27_tax_receipts where id=rid;
  insert into plone27_sales(tx,seller_account,buyer_account,base,iva,origin) values(f.tx,f.account_id,f.counterpart_account,base_,iva_,'regularizada');
  update plone27_iva_findings set status='regularizado',aprobado_por=p_actor,receipt_id=rid,iva_due=iva_,resolved_at=now() where id=p_finding;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_regularize','finding',p_finding::text,jsonb_build_object('recibo',rid,'iva',iva_));
  return rid; end $$;

create or replace function plone27_iva_report(p_desde date,p_hasta date) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'periodo',jsonb_build_object('desde',p_desde,'hasta',p_hasta),
    'ventas_registradas',(select jsonb_build_object('operaciones',count(*),'base',coalesce(sum(base),0),'iva',coalesce(sum(iva),0))
                          from plone27_sales where created_at::date between p_desde and p_hasta),
    'hallazgos_por_estado',coalesce((select jsonb_object_agg(q.status,jsonb_build_object('n',q.n,'importe',q.imp,'iva',q.iva))
                          from (select status,count(*) n,sum(amount) imp,coalesce(sum(iva_due),0) iva from plone27_iva_findings
                                where detected_at::date between p_desde and p_hasta group by status) q),'{}'::jsonb),
    'hallazgos_por_tipo',coalesce((select jsonb_object_agg(q.kind,jsonb_build_object('n',q.n,'importe',q.imp))
                          from (select kind,count(*) n,sum(amount) imp from plone27_iva_findings
                                where detected_at::date between p_desde and p_hasta group by kind) q),'{}'::jsonb),
    'iva_pendiente_de_liquidar',(select coalesce(sum(iva_due),0) from plone27_iva_findings where status='abierto'),
    'iva_regularizado',(select coalesce(sum(iva),0) from plone27_sales where origin='regularizada' and created_at::date between p_desde and p_hasta)) $$;

-- ========== 4. CERTIFICADOS: una modificación genera un certificado nuevo; el anterior queda intacto ==========
alter table plone27_tax_certificates drop constraint if exists plone27_tax_certificates_kind_subject_id_key;
alter table plone27_tax_certificates drop constraint if exists plone27_tax_certificates_kind_check;
do $$ begin alter table plone27_tax_certificates add constraint plone27_tax_certificates_kind_check
  check(kind in('recibo','regularizacion','recargo','rectificacion')) not valid; exception when duplicate_object then null; end $$;
alter table plone27_tax_certificates add column if not exists reemplaza uuid references plone27_tax_certificates(id),
  add column if not exists motivo text;
create index if not exists plone27_cert_subject_idx on plone27_tax_certificates(subject_id,seq);

create or replace function plone27_cert_insert(p_kind text,p_subject uuid,p_version uuid,p_base numeric,p_amount numeric,p_inputs jsonb,p_reemplaza uuid,p_motivo text)
returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare prev text; fp text; bt text:=p_base::numeric(18,2)::text; am text:=p_amount::numeric(18,2)::text; h text; cid uuid; begin
  perform pg_advisory_xact_lock(hashtext('plone27_cert'));
  select hash into prev from plone27_tax_certificates order by seq desc limit 1; prev:=coalesce(prev,'GENESIS');
  fp:=(select fingerprint from plone27_tax_rule_versions where id=p_version);
  h:=encode(sha256(convert_to(plone27_cert_text(prev,p_kind,p_subject,p_version,fp,bt,am,p_inputs),'utf8')),'hex');
  insert into plone27_tax_certificates(kind,subject_id,version_id,fingerprint,base,amount,inputs,prev_hash,hash,reemplaza,motivo)
    values(p_kind,p_subject,p_version,fp,p_base,p_amount,p_inputs,prev,h,p_reemplaza,p_motivo) returning id into cid;
  return cid; end $$;

create or replace function plone27_cert_append(p_kind text,p_subject uuid,p_version uuid,p_base numeric,p_amount numeric,p_inputs jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  return plone27_cert_insert(p_kind,p_subject,p_version,p_base,p_amount,p_inputs,null,null); end $$;

create or replace function plone27_cert_receipt_update() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare prevc uuid; begin
  select id into prevc from plone27_tax_certificates where subject_id=new.id order by seq desc limit 1;
  perform plone27_cert_insert('rectificacion',new.id,new.rule_version_id,new.base,new.amount,
    jsonb_build_object('tramos',plone27_tax_trace(new.rule_version_id,new.base),'cuenta',new.account_id,'obligado',new.obligor_account,
      'operacion',new.operation_ref,'importe_anterior',old.amount::text,'base_anterior',old.base::text),
    prevc,'Modificación del recibo: certificado nuevo; el certificado anterior no se altera');
  return null; end $$;
drop trigger if exists t_cert_receipt_upd on plone27_tax_receipts;
drop trigger if exists t_cert_receipt_upd on plone27_tax_receipts;
create trigger t_cert_receipt_upd after update of amount,base,rule_version_id on plone27_tax_receipts for each row
  when (old.amount is distinct from new.amount or old.base is distinct from new.base or old.rule_version_id is distinct from new.rule_version_id)
  execute function plone27_cert_receipt_update();

-- Certificado vigente de un recibo (el último de su historial) más el número de certificados que tiene
create or replace function plone27_receipt_certificate(p_receipt uuid) returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('recibo',r.ref,'norma',ru.code,'version',v.version,'huella_norma',c.fingerprint,'base',c.base,'importe',c.amount,
    'calculo',c.inputs,'tipo',c.kind,'seq',c.seq,'hash',c.hash,'hash_anterior',c.prev_hash,'reemplaza',c.reemplaza,
    'emitido',c.created_at,'certificados_del_recibo',(select count(*) from plone27_tax_certificates h where h.subject_id=p_receipt))
  from (select * from plone27_tax_certificates where subject_id=p_receipt order by seq desc limit 1) c
    join plone27_tax_receipts r on r.id=c.subject_id
    join plone27_tax_rule_versions v on v.id=c.version_id join plone27_tax_rules ru on ru.id=v.rule_id $$;

-- Informe de veracidad (sustituye al de 0012): cadena, cálculo, huellas, cambios sin certificado y recibos sin certificar
create or replace function plone27_certification_report() returns jsonb language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare c record; prev text:='GENESIS'; h text; total int:=0; rota int:=0; disc int:=0; alterados int; reg int:=0; fpd int; sin int; begin
  for c in select * from plone27_tax_certificates order by seq loop
    total:=total+1;
    if c.prev_hash<>prev then rota:=rota+1; end if;
    h:=encode(sha256(convert_to(plone27_cert_text(c.prev_hash,c.kind,c.subject_id,c.version_id,c.fingerprint,c.base::text,c.amount::text,c.inputs),'utf8')),'hex');
    if h<>c.hash then rota:=rota+1; end if;
    prev:=c.hash;
    if c.kind='recibo' then
      if plone27_tax_calc(c.version_id,c.base)<>c.amount then disc:=disc+1; end if;
    elsif c.kind='recargo' then
      if round(c.base*(c.inputs->>'tramo')::numeric/100,2)-(c.inputs->>'cobrado_previo')::numeric<>c.amount then disc:=disc+1; end if;
    else reg:=reg+1; end if;   -- regularizaciones y rectificaciones: informativas (importe acordado, no calculado)
  end loop;
  select count(*) into fpd from plone27_tax_rule_versions v where v.status='published' and v.fingerprint is distinct from plone27_version_fp(v.id);
  select count(*) into alterados from plone27_tax_receipts r
    join lateral (select c.amount,c.base from plone27_tax_certificates c where c.subject_id=r.id order by c.seq desc limit 1) u on true
    where r.amount<>u.amount or r.base<>u.base;
  select count(*) into sin from plone27_tax_receipts r where not exists(select 1 from plone27_tax_certificates c where c.subject_id=r.id);
  return jsonb_build_object('certificados',total,'cadena_rota',rota,'importes_no_recalculan',disc,'importes_sin_certificado_vigente',alterados,
    'huella_norma_discrepante',fpd,'recibos_sin_certificado',sin,'certificados_informativos',reg,
    'estado',case when rota+disc+alterados+fpd+sin=0 then 'OK' else 'REVISAR' end);
end $$;

-- ========== 5. RBU: el bono sale de la cuenta de origen configurada (con IBAN) ==========
create or replace function plone27_rbu_source() returns uuid language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_rbu_origen';
  if acc is null then acc:=plone27_reserve_account(); end if;
  return acc; end $$;

create or replace function plone27_rbu_claim(p_bonus uuid,p_user uuid,p_key text) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b plone27_rbu_bonuses; tx uuid; src uuid; begin
  select * into b from plone27_rbu_bonuses where id=p_bonus for update;
  if b.id is null or b.owner_user is distinct from p_user then raise exception 'Bono no encontrado'; end if;
  if b.status='claimed' then return b.claimed_tx; end if;
  if b.status<>'available' or b.expires_on<=current_date then raise exception 'Bono caducado'; end if;
  src:=plone27_rbu_source();
  if plone27_available(src)<b.amount then raise exception 'Cuenta de origen de la RBU sin fondos suficientes'; end if;
  tx:=plone27_transfer(p_key,src,b.wallet_account,b.amount,'RBU semanal',p_user);
  update plone27_rbu_bonuses set status='claimed',claimed_at=now(),claimed_tx=tx where id=p_bonus;
  return tx; end $$;

-- ========== 6. NÓMINAS: cotizaciones a su propia cuenta recaudadora; SMI mensual de 160 Pz ==========
create or replace function plone27_contract_guard() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare smi numeric; ek text; wk text; begin
  select kind into ek from plone27_accounts where id=new.employer_account and bank_id=new.bank_id;
  select kind into wk from plone27_accounts where id=new.worker_account and bank_id=new.bank_id;
  if ek is distinct from 'business' then raise exception 'La cuenta empleadora debe ser de empresa de la entidad'; end if;
  if wk is distinct from 'personal' then raise exception 'La cuenta del trabajador debe ser personal de la entidad'; end if;
  smi:=(plone27_setting('smi_mensual_completa_pz',new.bank_id)#>>'{}')::numeric;
  if new.gross_monthly<smi then raise exception 'Contrato no válido: el bruto mensual está por debajo del SMI (% Pz al mes)',smi; end if;
  return new; end $$;

create or replace function plone27_payroll_run(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c record; v_wt uuid; v_we uuid; v_ir uuid; col_t uuid; col_e uuid; col_irp uuid; wc numeric; ec numeric; ir numeric; lines jsonb; tx uuid; ok int:=0; ko int:=0; begin
  select collector_account into col_t from plone27_tax_rules where code='COT_TRA';
  select collector_account into col_e from plone27_tax_rules where code='COT_EMP';
  select collector_account into col_irp from plone27_tax_rules where code='IRP';
  for c in select * from plone27_contracts where status='active' and next_pay<=current_date order by next_pay,id loop
    begin
      v_wt:=plone27_active_version('COT_TRA',c.next_pay); v_we:=plone27_active_version('COT_EMP',c.next_pay); v_ir:=plone27_active_version('IRP',c.next_pay);
      if v_wt is null or v_we is null or v_ir is null or col_t is null or col_e is null or col_irp is null then raise exception 'Falta una norma publicada o un destino (COT_TRA, COT_EMP, IRP)'; end if;
      wc:=plone27_tax_calc(v_wt,c.gross_monthly); ec:=plone27_tax_calc(v_we,c.gross_monthly); ir:=plone27_tax_calc(v_ir,c.gross_monthly);
      select jsonb_agg(l) into lines from (
        select jsonb_build_object('account',c.employer_account,'dir','debit','amount',c.gross_monthly+ec) l
        union all select jsonb_build_object('account',c.worker_account,'dir','credit','amount',c.gross_monthly-wc-ir)
        union all select jsonb_build_object('account',col_t,'dir','credit','amount',wc)
        union all select jsonb_build_object('account',col_e,'dir','credit','amount',ec)
        union all select jsonb_build_object('account',col_irp,'dir','credit','amount',ir)) x
        where (l->>'amount')::numeric>0;
      tx:=plone27_post('nomina:'||c.id||':'||c.next_pay,'payroll','Nómina '||to_char(c.next_pay,'YYYY-MM'),lines,p_actor);
      insert into plone27_payslips(contract_id,pay_date,gross,worker_contrib,employer_contrib,irp,net,tx)
        values(c.id,c.next_pay,c.gross_monthly,wc,ec,ir,c.gross_monthly-wc-ir,tx) on conflict(contract_id,pay_date) do nothing;
      update plone27_contracts set next_pay=plone27_add_months(c.next_pay,1,c.pay_day) where id=c.id;
      ok:=ok+1;
    exception when others then
      insert into plone27_incidents(kind,detail) values('nomina_fallida',jsonb_build_object('contrato',c.id,'err',sqlerrm)); ko:=ko+1;
    end;
  end loop;
  return jsonb_build_object('pagadas',ok,'fallidas',ko);
end $$;

-- ========== 7. EJECUCIÓN DIARIA: añade el escaneo de IVA ==========
create or replace function plone27_finanzas_daily(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb:='{}'::jsonb; begin
  begin r:=r||jsonb_build_object('rbu_caducados',plone27_rbu_expire(p_actor)); exception when others then perform plone27_log_step('rbu_caducados',sqlerrm); end;
  begin r:=r||jsonb_build_object('rbu_emitidos',plone27_rbu_issue_week(date_trunc('week',current_date)::date,p_actor)); exception when others then perform plone27_log_step('rbu_emitidos',sqlerrm); end;
  begin r:=r||jsonb_build_object('programadas',plone27_run_scheduled(p_actor)); exception when others then perform plone27_log_step('programadas',sqlerrm); end;
  begin r:=r||jsonb_build_object('cuotas_producto',plone27_charge_product_fees(p_actor)); exception when others then perform plone27_log_step('cuotas_producto',sqlerrm); end;
  begin r:=r||jsonb_build_object('interes_credito',plone27_accrue_interest(p_actor)); exception when others then perform plone27_log_step('interes_credito',sqlerrm); end;
  begin r:=r||jsonb_build_object('membresias',plone27_subscriptions_sweep(p_actor)); exception when others then perform plone27_log_step('membresias',sqlerrm); end;
  begin r:=r||jsonb_build_object('nominas',plone27_payroll_run(p_actor)); exception when others then perform plone27_log_step('nominas',sqlerrm); end;
  begin r:=r||jsonb_build_object('planes',plone27_plans_collect(p_actor)); exception when others then perform plone27_log_step('planes',sqlerrm); end;
  begin r:=r||jsonb_build_object('iaep',plone27_iaep_monthly(current_date,p_actor)); exception when others then perform plone27_log_step('iaep',sqlerrm); end;
  begin r:=r||jsonb_build_object('mora',plone27_mora_run(p_actor)); exception when others then perform plone27_log_step('mora',sqlerrm); end;
  begin r:=r||jsonb_build_object('recargos_T57',plone27_t57_run(p_actor)); exception when others then perform plone27_log_step('recargos_T57',sqlerrm); end;
  begin r:=r||jsonb_build_object('iva_escaneo',plone27_iva_scan(now()-interval '2 days',now()+interval '1 minute',p_actor)); exception when others then perform plone27_log_step('iva_escaneo',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_recibos',plone27_autocollect_taxes(p_actor)); exception when others then perform plone27_log_step('cobro_recibos',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_deudas',plone27_autocollect_debts(p_actor)); exception when others then perform plone27_log_step('cobro_deudas',sqlerrm); end;
  begin r:=r||jsonb_build_object('certificacion',plone27_certification_report());
    if r->'certificacion'->>'estado'<>'OK' then insert into plone27_incidents(kind,detail) values('certificacion',r->'certificacion'); end if;
  exception when others then perform plone27_log_step('certificacion',sqlerrm); end;
  return r;
end $$;

-- ========== 8. SEGURIDAD (mismo patrón que 0001–0012) ==========
do $$ declare t text; f text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0014_plone27_cierre_estadisticas.sql) ====================
-- Placeta One · 0014 · Cierre mensual certificado, presunción de ventas con IVA, criterio de retención,
-- pagador configurable para Junior, estadísticas y vistas de análisis. Requiere 0013. Idempotente.

-- ========== 1. AJUSTES ==========
insert into plone27_settings(key,category,description,vtype,allowed,min_v,max_v,value,sensitive,bank_overridable) values
('dia_cierre','fiscalidad','Día del mes en que se cierra el mes anterior (liquidación e impuestos periódicos)','number',null,1,28,'6',true,false),
('cierre_umbral_retencion','fiscalidad','Importe (Pz) de una declaración a partir del cual el cierre la retiene para aprobación','number',null,0,1000000000,'50000',true,false),
('cierre_variacion_retencion_pct','fiscalidad','Subida (%) frente al cierre anterior a partir de la cual el cierre retiene la declaración','number',null,0,10000,'300',true,false)
on conflict(key) do nothing;

-- ========== 2. RESTRICCIONES AMPLIADAS ==========
alter table plone27_sales drop constraint if exists plone27_sales_origin_check;
do $$ begin alter table plone27_sales add constraint plone27_sales_origin_check check(origin in('plataforma','regularizada','presunta')) not valid; exception when duplicate_object then null; end $$;
alter table plone27_iva_findings drop constraint if exists plone27_iva_findings_status_check;
do $$ begin alter table plone27_iva_findings add constraint plone27_iva_findings_status_check check(status in('abierto','presumido','regularizado','descartado')) not valid; exception when duplicate_object then null; end $$;
alter table plone27_tax_certificates drop constraint if exists plone27_tax_certificates_kind_check;
do $$ begin alter table plone27_tax_certificates add constraint plone27_tax_certificates_kind_check check(kind in('recibo','regularizacion','recargo','rectificacion','cierre')) not valid; exception when duplicate_object then null; end $$;

-- ========== 3. TABLAS NUEVAS ==========
create table if not exists plone27_periodos(
  id uuid primary key default gen_random_uuid(),
  periodo date not null unique,                       -- primer día del mes
  estado text not null default 'abierto' check(estado in('abierto','cerrado')),
  declaraciones int not null default 0, emitidas int not null default 0, retenidas int not null default 0, sin_norma int not null default 0,
  importe_total numeric(18,2) not null default 0,
  cerrado_at timestamptz, cerrado_por uuid, cierre_cert uuid);

create table if not exists plone27_declaraciones(
  id uuid primary key default gen_random_uuid(),
  periodo_id uuid not null references plone27_periodos,
  account_id uuid not null references plone27_accounts,
  impuesto text not null,
  base numeric(18,2) not null default 0,
  importe numeric(18,2),                              -- null = sin norma publicada
  fuente text not null check(fuente in('libro','presunta')),
  estado text not null check(estado in('emitida','retenida','sin_norma','exento','aprobada')),
  motivo_retencion text,
  receipt_id uuid references plone27_tax_receipts,
  saldo_arrastre numeric(18,2) not null default 0,    -- IVA: base pendiente que pasa al siguiente cierre
  detalle jsonb not null default '{}'::jsonb,
  aprobado_por uuid, aprobado_at timestamptz,
  created_at timestamptz not null default now(),
  unique(periodo_id,account_id,impuesto));

create table if not exists plone27_ajustes_iva(
  id uuid primary key default gen_random_uuid(),
  finding_id uuid not null unique references plone27_iva_findings,
  account_id uuid not null references plone27_accounts,
  base numeric(18,2) not null,                        -- negativa: anula una presunción justificada
  motivo text not null,
  aplicado_en uuid references plone27_periodos,
  created_at timestamptz not null default now());

create table if not exists plone27_metricas(
  fecha date not null, area text not null, metrica text not null, dimension text not null default '',
  valor numeric not null, primary key(fecha,area,metrica,dimension));

-- ========== 4. BASES DE CADA IMPUESTO (criterio fijado en la normativa, sobre el libro) ==========
create or replace function plone27_base_impuesto(p_acc uuid,p_impuesto text,p_desde timestamptz,p_hasta timestamptz) returns numeric
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare r numeric:=0; begin
  if p_impuesto='IRM' then
    select coalesce(sum(e.amount),0) into r from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
     where e.account_id=p_acc and e.direction='debit' and t.kind='transfer' and t.status='posted' and t.created_at>=p_desde and t.created_at<p_hasta
       and exists(select 1 from plone27_ledger_entries c where c.transaction_id=t.id and c.direction='credit' and not plone27_es_institucional(c.account_id));
  elsif p_impuesto='IRP' then
    select coalesce(sum(e.amount),0) into r from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
     where e.account_id=p_acc and e.direction='credit' and t.kind='transfer' and t.status='posted' and t.created_at>=p_desde and t.created_at<p_hasta
       and exists(select 1 from plone27_ledger_entries c where c.transaction_id=t.id and c.direction='debit' and not plone27_es_institucional(c.account_id));
  elsif p_impuesto in('IGF','IPE') then
    select greatest(0,coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0)) into r
     from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
     where e.account_id=p_acc and t.created_at<p_hasta;
  elsif p_impuesto='IBA' then
    select greatest(0,
      coalesce((select sum(s.base) from plone27_sales s where s.seller_account=p_acc and s.created_at>=p_desde and s.created_at<p_hasta),0)
      -coalesce((select sum(s.base) from plone27_sales s where s.buyer_account=p_acc and s.created_at>=p_desde and s.created_at<p_hasta),0)
      -coalesce((select sum(p.gross+p.employer_contrib) from plone27_payslips p join plone27_contracts c on c.id=p.contract_id
                 where c.employer_account=p_acc and p.pay_date>=p_desde::date and p.pay_date<p_hasta::date),0)) into r;
  elsif p_impuesto='ITP' then
    select coalesce(sum(e.amount),0) into r from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
     where e.account_id=p_acc and e.direction='debit' and t.kind='transfer' and t.status='posted' and t.created_at>=p_desde and t.created_at<p_hasta
       and exists(select 1 from plone27_ledger_entries c join plone27_accounts ca on ca.id=c.account_id
                  where c.transaction_id=t.id and c.direction='credit' and ca.kind='business'
                    and ca.owner_user is distinct from (select owner_user from plone27_accounts where id=p_acc));
  end if;
  return round(coalesce(r,0),2);
end $$;

-- ========== 5. VENTAS: el IVA ya no se cobra venta a venta; lo liquida el cierre mensual ==========
create or replace function plone27_sale(p_key text,p_buyer uuid,p_seller uuid,p_base numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare vid uuid; iva numeric:=0; tx uuid; begin
  if p_base<=0 then raise exception 'Base de venta no válida'; end if;
  vid:=plone27_active_version('IVA',current_date);
  if vid is not null and not exists(select 1 from plone27_tax_exemptions e join plone27_tax_rules ru on ru.id=e.rule_id
       where ru.code='IVA' and e.account_id=p_seller and current_date>=e.valid_from and (e.valid_to is null or current_date<=e.valid_to)) then
    iva:=plone27_tax_calc(vid,p_base);
  end if;
  tx:=plone27_transfer(p_key,p_buyer,p_seller,p_base+iva,'Venta · base '||p_base::text||' · IVA '||iva::text,p_actor);
  insert into plone27_sales(tx,seller_account,buyer_account,base,iva,origin) values(tx,p_seller,p_buyer,p_base,iva,'plataforma');
  return tx; end $$;

create or replace function plone27_iva_propose(p_finding uuid,p_accion text,p_motivo text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if p_accion not in('regularizar','descartar') then raise exception 'Acción no válida'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  update plone27_iva_findings set propuesta_accion=p_accion,motivo=p_motivo,propuesto_por=p_actor
   where id=p_finding and (status='abierto' or (status='presumido' and p_accion='descartar'));
  if not found then raise exception 'Hallazgo no abierto (o presumido solo se puede descartar)'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_propose','finding',p_finding::text,jsonb_build_object('accion',p_accion,'motivo',p_motivo));
end $$;

-- Aprobación: regularizar registra la venta (se liquida en el cierre del mes); descartar un hallazgo presumido crea un ajuste para el siguiente cierre.
create or replace function plone27_iva_approve(p_finding uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f plone27_iva_findings; bs numeric; ivs numeric; begin
  select * into f from plone27_iva_findings where id=p_finding for update;
  if f.id is null or f.status not in('abierto','presumido') then raise exception 'Hallazgo no abierto ni presumido'; end if;
  if f.propuesta_accion is null then raise exception 'Falta una propuesta'; end if;
  if f.propuesto_por is not distinct from p_actor then raise exception 'Quien propone no puede aprobar'; end if;
  if f.propuesta_accion='descartar' then
    if f.status='presumido' then
      select s.base into bs from plone27_sales s where s.tx=f.tx;
      insert into plone27_ajustes_iva(finding_id,account_id,base,motivo) values(f.id,f.account_id,-coalesce(bs,0),f.motivo);
    end if;
    update plone27_iva_findings set status='descartado',aprobado_por=p_actor,resolved_at=now() where id=p_finding;
    insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_discard','finding',p_finding::text,jsonb_build_object('estado_previo',f.status));
    return null;
  end if;
  if f.status='presumido' then raise exception 'Ya presumido: solo se puede descartar'; end if;
  if f.kind<>'cobro_comercial_sin_iva' then raise exception 'Solo se regulariza un cobro comercial sin IVA'; end if;
  select sp.base,sp.iva into bs,ivs from plone27_iva_split(f.amount) sp;
  insert into plone27_sales(tx,seller_account,buyer_account,base,iva,origin) values(f.tx,f.account_id,f.counterpart_account,bs,ivs,'regularizada');
  update plone27_iva_findings set status='regularizado',aprobado_por=p_actor,resolved_at=now() where id=p_finding;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_regularize','finding',p_finding::text,jsonb_build_object('base',bs));
  return null; end $$;

-- ========== 6. REGISTRO DE UNA DECLARACIÓN DEL CIERRE (criterio de retención incluido) ==========
create or replace function plone27_cierre_registrar(p_per uuid,p_ini date,p_fin date,p_acc uuid,p_impuesto text,p_base numeric,p_fuente text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare vid uuid; imp numeric; prev numeric; ret boolean:=false; motivo text; estado text; rid uuid; carry numeric:=0; k text; tipo text;
  due date:=p_fin+(plone27_setting('default_receipt_due_days')#>>'{}')::int;
  umbral numeric:=(plone27_setting('cierre_umbral_retencion')#>>'{}')::numeric;
  varpct numeric:=(plone27_setting('cierre_variacion_retencion_pct')#>>'{}')::numeric; begin
  vid:=plone27_active_version(p_impuesto,p_fin-1);
  if vid is null then
    imp:=null; estado:='sin_norma'; carry:=case when p_impuesto='IVA' then p_base else 0 end;
  elsif p_base<=0 then
    imp:=0; estado:='emitida'; carry:=case when p_impuesto='IVA' then p_base else 0 end;
  else
    imp:=plone27_tax_calc(vid,p_base);
    select d.importe into prev from plone27_declaraciones d join plone27_periodos pp on pp.id=d.periodo_id
      where d.account_id=p_acc and d.impuesto=p_impuesto and pp.periodo<p_ini and d.importe is not null order by pp.periodo desc limit 1;
    if imp>=umbral then ret:=true; motivo:='importe igual o superior al umbral de '||umbral::text||' Pz';
    elsif prev is not null and prev>0 and imp>prev*(1+varpct/100) then ret:=true; motivo:='subida superior al '||varpct::text||' % frente al cierre anterior ('||prev::text||' Pz)';
    end if;
    if ret then estado:='retenida';
    elsif imp=0 then estado:='emitida';
    else
      select a.kind into tipo from plone27_accounts a where a.id=p_acc;
      k:='cierre:'||p_impuesto||':'||p_acc::text||':'||p_ini::text;
      if tipo='junior' then rid:=plone27_tax_issue_junior(p_impuesto,p_acc,p_base,k,null,'periodica',due,p_actor);
      else rid:=plone27_tax_issue(p_impuesto,p_acc,p_base,k,null,'periodica',due,p_actor); end if;
      estado:=case when rid is null then 'exento' else 'emitida' end;
    end if;
  end if;
  insert into plone27_declaraciones(periodo_id,account_id,impuesto,base,importe,fuente,estado,motivo_retencion,receipt_id,saldo_arrastre,detalle)
    values(p_per,p_acc,p_impuesto,p_base,imp,p_fuente,estado,motivo,rid,carry,jsonb_build_object('version',vid,'anterior',prev))
    on conflict(periodo_id,account_id,impuesto) do nothing;
  return estado;
end $$;

-- Aprobar una declaración retenida: emite su recibo. Lo hace una persona con rol aprobador.
create or replace function plone27_declaracion_aprobar(p_decl uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_declaraciones; tipo text; rid uuid; k text; due date:=current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int; begin
  select * into d from plone27_declaraciones where id=p_decl for update;
  if d.id is null or d.estado<>'retenida' then raise exception 'La declaración no está retenida'; end if;
  select a.kind into tipo from plone27_accounts a where a.id=d.account_id;
  k:='aprobada:'||d.id::text;
  if tipo='junior' then rid:=plone27_tax_issue_junior(d.impuesto,d.account_id,d.base,k,null,'periodica',due,p_actor);
  else rid:=plone27_tax_issue(d.impuesto,d.account_id,d.base,k,null,'periodica',due,p_actor); end if;
  update plone27_declaraciones set estado=case when rid is null then 'exento' else 'aprobada' end,receipt_id=rid,aprobado_por=p_actor,aprobado_at=now() where id=p_decl;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'declaracion_aprobar','declaracion',p_decl::text,jsonb_build_object('recibo',rid));
  return rid; end $$;

-- ========== 7. CIERRE MENSUAL ==========
create or replace function plone27_cierre_mensual(p_periodo date,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ini date:=date_trunc('month',p_periodo)::date; fin date:=(date_trunc('month',p_periodo)+interval '1 month')::date;
  per plone27_periodos; f record; a record; ac record; bs numeric; ivs numeric; dev numeric; sop numeric; carry numeric; net numeric;
  estado text; presum int:=0; tot numeric; n int; cnt_e int; cnt_r int; cnt_s int; hash text; cert uuid; begin
  select * into per from plone27_periodos where periodo=ini;
  if per.id is not null and per.estado='cerrado' then return jsonb_build_object('periodo',ini,'estado','ya_cerrado'); end if;
  if per.id is null then insert into plone27_periodos(periodo) values(ini) returning * into per; end if;

  -- a) cobros comerciales sin venta registrada del mes: se presumen venta gravada
  for f in select fi.id,fi.tx,fi.account_id,fi.counterpart_account,fi.amount from plone27_iva_findings fi
    join plone27_transactions t on t.id=fi.tx
    where fi.kind='cobro_comercial_sin_iva' and fi.status='abierto' and t.created_at>=ini and t.created_at<fin loop
    select sp.base,sp.iva into bs,ivs from plone27_iva_split(f.amount) sp;
    insert into plone27_sales(tx,seller_account,buyer_account,base,iva,origin,created_at)
      select f.tx,f.account_id,f.counterpart_account,bs,ivs,'presunta',t.created_at from plone27_transactions t where t.id=f.tx
      on conflict(tx) do nothing;
    update plone27_iva_findings set status='presumido' where id=f.id;
    presum:=presum+1;
  end loop;

  -- b) IVA: base devengada − base soportada (+ arrastre) por titular
  for ac in select distinct x.acc from (
      select s.seller_account acc from plone27_sales s where s.created_at>=ini and s.created_at<fin
      union select s.buyer_account from plone27_sales s join plone27_accounts b on b.id=s.buyer_account
        where s.created_at>=ini and s.created_at<fin and b.kind='business'
      union select j.account_id from plone27_ajustes_iva j where j.aplicado_en is null and j.created_at<fin) x
    where x.acc is not null loop
    select coalesce(sum(s.base),0) into dev from plone27_sales s where s.seller_account=ac.acc and s.created_at>=ini and s.created_at<fin;
    dev:=dev+coalesce((select sum(j.base) from plone27_ajustes_iva j where j.account_id=ac.acc and j.aplicado_en is null and j.created_at<fin),0);
    select coalesce(sum(s.base),0) into sop from plone27_sales s join plone27_accounts b on b.id=s.buyer_account
      where s.buyer_account=ac.acc and b.kind='business' and s.created_at>=ini and s.created_at<fin;
    carry:=coalesce((select d.saldo_arrastre from plone27_declaraciones d join plone27_periodos pp on pp.id=d.periodo_id
      where d.account_id=ac.acc and d.impuesto='IVA' and pp.periodo<ini order by pp.periodo desc limit 1),0);
    net:=dev-sop+carry;
    estado:=plone27_cierre_registrar(per.id,ini,fin,ac.acc,'IVA',net,
      case when exists(select 1 from plone27_sales s where s.seller_account=ac.acc and s.origin='presunta' and s.created_at>=ini and s.created_at<fin)
           then 'presunta' else 'libro' end,p_actor);
    update plone27_ajustes_iva set aplicado_en=per.id where account_id=ac.acc and aplicado_en is null and created_at<fin;
  end loop;

  -- c) impuestos periódicos sobre el libro: personas (IRM, IRP, IGF) y empresas (IRM, IBA, IPE, ITP)
  for a in select id,kind from plone27_accounts where status='active' and kind in('personal','junior','business') loop
    for ac in select unnest(case when a.kind='business' then array['IRM','IBA','IPE','ITP'] else array['IRM','IRP','IGF'] end) as imp loop
      bs:=plone27_base_impuesto(a.id,ac.imp,ini::timestamptz,fin::timestamptz);
      if bs>0 then estado:=plone27_cierre_registrar(per.id,ini,fin,a.id,ac.imp,bs,'libro',p_actor); end if;
    end loop;
  end loop;

  -- d) totales y certificado del cierre (la huella cubre todas las declaraciones)
  select count(*),count(*) filter(where estado='emitida' and importe>0),count(*) filter(where estado='retenida'),count(*) filter(where estado='sin_norma'),
         coalesce(sum(importe) filter(where estado in('emitida','aprobada')),0)
    into n,cnt_e,cnt_r,cnt_s,tot from plone27_declaraciones where periodo_id=per.id;
  select encode(sha256(convert_to(coalesce(string_agg(d.account_id::text||'|'||d.impuesto||'|'||d.base::text||'|'||coalesce(d.importe::text,'-')||'|'||d.estado,';' order by d.account_id::text,d.impuesto),''),'utf8')),'hex')
    into hash from plone27_declaraciones d where d.periodo_id=per.id;
  cert:=plone27_cert_insert('cierre',per.id,null,0,tot,jsonb_build_object('periodo',ini,'declaraciones',n,'huella_declaraciones',hash),null,'Cierre mensual');
  update plone27_periodos set estado='cerrado',declaraciones=n,emitidas=cnt_e,retenidas=cnt_r,sin_norma=cnt_s,importe_total=tot,
    cerrado_at=now(),cerrado_por=p_actor,cierre_cert=cert where id=per.id;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor) values
    (fin-1,'cierre','declaraciones',ini::text,n),(fin-1,'cierre','retenidas',ini::text,cnt_r),(fin-1,'cierre','importe',ini::text,tot),(fin-1,'cierre','presunciones',ini::text,presum)
    on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  return jsonb_build_object('periodo',ini,'estado','cerrado','presunciones',presum,'declaraciones',n,'emitidas',cnt_e,
                            'retenidas',cnt_r,'sin_norma',cnt_s,'importe',tot,'certificado',cert);
end $$;

-- ========== 8. PAGADOR DE IMPUESTOS JUNIOR CONFIGURABLE (Capitalia, o la cuenta que se designe) ==========
create or replace function plone27_junior_tax_payer() returns uuid language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  select nullif(value,'')::uuid into acc from plone27_config where key='pagador_impuestos_junior';
  if acc is not null then return acc; end if;
  if (plone27_setting('capitalia_asume_impuestos_junior')#>>'{}')::boolean then
    select bk.main_account into acc from plone27_config c join plone27_banks bk on bk.id=nullif(c.value,'')::uuid where c.key='entidad_capitalia';
    if acc is null then raise exception 'Capitalia no tiene cuenta principal configurada'; end if;
  else
    select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_placeta_junior';
    if acc is null then raise exception 'Falta la cuenta de Placeta Junior (seed 0011)'; end if;
  end if;
  return acc; end $$;

create or replace function plone27_config_set(p_key text,p_account uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  if p_key not in('cuenta_tributos','cuenta_rbu_origen','pagador_impuestos_junior') then raise exception 'Clave no permitida: %',p_key; end if;
  if not plone27_es_institucional(p_account) then raise exception 'La cuenta debe ser institucional'; end if;
  insert into plone27_config(key,value) values(p_key,p_account::text) on conflict(key) do update set value=excluded.value;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'config_set','config',p_key,jsonb_build_object('cuenta',p_account));
end $$;

-- ========== 9. ESTADÍSTICAS (una fila por fecha, área, métrica y dimensión) ==========
create or replace function plone27_estadisticas_dia(p_fecha date,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ini timestamptz:=p_fecha::timestamptz; fin timestamptz:=(p_fecha+1)::timestamptz; n int; begin
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'transacciones','numero',t.kind,count(*) from plone27_transactions t where t.created_at>=ini and t.created_at<fin group by t.kind
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'transacciones','volumen',t.kind,sum(e.amount) from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
     where e.direction='debit' and t.created_at>=ini and t.created_at<fin group by t.kind
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'entidades','volumen',coalesce(b.code,'sin_entidad'),sum(e.amount) from plone27_ledger_entries e
     join plone27_transactions t on t.id=e.transaction_id join plone27_accounts a on a.id=e.account_id left join plone27_banks b on b.id=a.bank_id
     where e.direction='debit' and t.created_at>=ini and t.created_at<fin group by coalesce(b.code,'sin_entidad')
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'saldos','total',a.kind,sum(case when e.direction='credit' then e.amount else -e.amount end) from plone27_ledger_entries e
     join plone27_transactions t on t.id=e.transaction_id join plone27_accounts a on a.id=e.account_id where t.created_at<fin group by a.kind
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'recibos','emitidos_numero',ru.code,count(*) from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
     join plone27_tax_rules ru on ru.id=v.rule_id where r.created_at>=ini and r.created_at<fin group by ru.code
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'recibos','emitidos_importe',ru.code,sum(r.amount) from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
     join plone27_tax_rules ru on ru.id=v.rule_id where r.created_at>=ini and r.created_at<fin group by ru.code
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'iva','ventas_base',s.origin,sum(s.base) from plone27_sales s where s.created_at>=ini and s.created_at<fin group by s.origin
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'iva','hallazgos',fi.severity,count(*) from plone27_iva_findings fi where fi.detected_at>=ini and fi.detected_at<fin group by fi.severity
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'nominas','netos_pagados','total',coalesce(sum(p.net),0) from plone27_payslips p where p.pay_date=p_fecha
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'rbu','reclamadas','total',count(*) from plone27_rbu_bonuses b where b.claimed_at>=ini and b.claimed_at<fin
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'planes','cuotas_cobradas_importe','total',coalesce(sum(i.principal_part+i.interest_part),0) from plone27_plan_items i
     where i.paid_at>=ini and i.paid_at<fin
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'incidencias','abiertas',coalesce(x.kind,'sin_tipo'),count(*) from plone27_incidents x where x.at>=ini and x.at<fin group by coalesce(x.kind,'sin_tipo')
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'certificados','emitidos',c.kind,count(*) from plone27_tax_certificates c where c.created_at>=ini and c.created_at<fin group by c.kind
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  insert into plone27_metricas(fecha,area,metrica,dimension,valor)
    select p_fecha,'usuarios','cuentas_nuevas',a.kind,count(*) from plone27_accounts a where a.created_at>=ini and a.created_at<fin group by a.kind
  on conflict(fecha,area,metrica,dimension) do update set valor=excluded.valor;
  n:=(select count(*) from plone27_metricas where fecha=p_fecha);
  return n; end $$;

-- ========== 10. VISTAS DE ANÁLISIS (planas, para cualquier cruce) ==========
drop view if exists plone27_v_movimientos cascade;
create view plone27_v_movimientos with(security_invoker=true) as
  select e.id,e.created_at,t.id tx_id,t.kind,t.status,t.memo,e.direction,e.amount,
         a.id account_id,a.iban,a.name account_name,a.kind account_kind,a.owner_user,b.code bank_code,b.name bank_name
  from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
  join plone27_accounts a on a.id=e.account_id left join plone27_banks b on b.id=a.bank_id;

drop view if exists plone27_v_declaraciones cascade;
create view plone27_v_declaraciones with(security_invoker=true) as
  select d.id,p.periodo,a.iban,a.name account_name,a.kind account_kind,d.impuesto,d.base,d.importe,d.estado,d.fuente,
         d.motivo_retencion,d.saldo_arrastre,d.receipt_id,d.aprobado_por,d.aprobado_at
  from plone27_declaraciones d join plone27_periodos p on p.id=d.periodo_id join plone27_accounts a on a.id=d.account_id;

drop view if exists plone27_v_recibos cascade;
create view plone27_v_recibos with(security_invoker=true) as
  select r.id,r.ref,r.created_at,ru.code impuesto,a.iban,a.kind account_kind,r.base,r.amount,r.paid_amount,r.status,r.due_date,
         r.obligor_account,r.operation_ref
  from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
  join plone27_tax_rules ru on ru.id=v.rule_id join plone27_accounts a on a.id=r.account_id;

-- ========== 11. EJECUCIÓN DIARIA: cierre mensual y estadísticas de ayer ==========
create or replace function plone27_finanzas_daily(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb:='{}'::jsonb; begin
  begin r:=r||jsonb_build_object('rbu_caducados',plone27_rbu_expire(p_actor)); exception when others then perform plone27_log_step('rbu_caducados',sqlerrm); end;
  begin r:=r||jsonb_build_object('rbu_emitidos',plone27_rbu_issue_week(date_trunc('week',current_date)::date,p_actor)); exception when others then perform plone27_log_step('rbu_emitidos',sqlerrm); end;
  begin r:=r||jsonb_build_object('programadas',plone27_run_scheduled(p_actor)); exception when others then perform plone27_log_step('programadas',sqlerrm); end;
  begin r:=r||jsonb_build_object('cuotas_producto',plone27_charge_product_fees(p_actor)); exception when others then perform plone27_log_step('cuotas_producto',sqlerrm); end;
  begin r:=r||jsonb_build_object('interes_credito',plone27_accrue_interest(p_actor)); exception when others then perform plone27_log_step('interes_credito',sqlerrm); end;
  begin r:=r||jsonb_build_object('membresias',plone27_subscriptions_sweep(p_actor)); exception when others then perform plone27_log_step('membresias',sqlerrm); end;
  begin r:=r||jsonb_build_object('nominas',plone27_payroll_run(p_actor)); exception when others then perform plone27_log_step('nominas',sqlerrm); end;
  begin r:=r||jsonb_build_object('planes',plone27_plans_collect(p_actor)); exception when others then perform plone27_log_step('planes',sqlerrm); end;
  begin r:=r||jsonb_build_object('iaep',plone27_iaep_monthly(current_date,p_actor)); exception when others then perform plone27_log_step('iaep',sqlerrm); end;
  begin r:=r||jsonb_build_object('mora',plone27_mora_run(p_actor)); exception when others then perform plone27_log_step('mora',sqlerrm); end;
  begin r:=r||jsonb_build_object('recargos_T57',plone27_t57_run(p_actor)); exception when others then perform plone27_log_step('recargos_T57',sqlerrm); end;
  begin r:=r||jsonb_build_object('iva_escaneo',plone27_iva_scan(now()-interval '2 days',now()+interval '1 minute',p_actor)); exception when others then perform plone27_log_step('iva_escaneo',sqlerrm); end;
  begin
    if extract(day from current_date)>=(plone27_setting('dia_cierre')#>>'{}')::int then
      r:=r||jsonb_build_object('cierre_mensual',plone27_cierre_mensual((date_trunc('month',current_date)-interval '1 month')::date,p_actor));
    end if;
  exception when others then perform plone27_log_step('cierre_mensual',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_recibos',plone27_autocollect_taxes(p_actor)); exception when others then perform plone27_log_step('cobro_recibos',sqlerrm); end;
  begin r:=r||jsonb_build_object('cobro_deudas',plone27_autocollect_debts(p_actor)); exception when others then perform plone27_log_step('cobro_deudas',sqlerrm); end;
  begin r:=r||jsonb_build_object('certificacion',plone27_certification_report());
    if r->'certificacion'->>'estado'<>'OK' then insert into plone27_incidents(kind,detail) values('certificacion',r->'certificacion'); end if;
  exception when others then perform plone27_log_step('certificacion',sqlerrm); end;
  begin r:=r||jsonb_build_object('estadisticas',plone27_estadisticas_dia(current_date-1,p_actor)); exception when others then perform plone27_log_step('estadisticas',sqlerrm); end;
  return r;
end $$;

-- ========== 12. SEGURIDAD: RLS en tablas, vistas solo para service_role, funciones solo para service_role ==========
do $$ declare t text; f text; v text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for v in select viewname from pg_views where schemaname='public' and viewname like 'plone27\_v\_%' loop
    execute format('revoke all on %I from anon, authenticated',v); execute format('grant select on %I to service_role',v); end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0015_plone27_previsiones.sql) ====================
-- Placeta One · 0015 · Previsión de movimientos programados e indicadores del panel. Requiere 0014. Idempotente.

-- Previsión: todo lo que va a ocurrir en un rango de fechas, con si la cuenta puede pagarlo.
create or replace function plone27_previsiones(p_desde date,p_hasta date) returns table(
  fecha date, tipo text, referencia text, cuenta uuid, iban text, nombre text, importe numeric, estado text, detalle text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
  select u.* from (
    -- Impuestos: recibos pendientes (vencidos o con vencimiento en el rango)
    -- Los alias de la PRIMERA rama dan nombre a las columnas del UNION (fecha, tipo, …)
    select r.due_date as fecha, 'Impuesto'::text as tipo, (ru.code||' · '||coalesce(r.ref,'sin referencia'))::text as referencia,
           r.account_id as cuenta, a.iban as iban, a.name as nombre,
           (r.amount-r.paid_amount)::numeric as importe,
           (case when r.due_date<current_date then 'vencido'
                 when plone27_collectable(r.account_id,r.amount-r.paid_amount) then 'cobrable' else 'sin fondos' end)::text as estado,
           ('Vence el '||r.due_date::text)::text as detalle
    from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
      join plone27_tax_rules ru on ru.id=v.rule_id join plone27_accounts a on a.id=r.account_id
    where r.status in('issued','partial') and r.amount-r.paid_amount>0 and r.due_date between p_desde and p_hasta
    union all
    -- Cuotas de planes a plazos
    select i.due_date, 'Cuota'::text, ('Plan '||left(p.id::text,8)||' · cuota '||i.seq)::text, p.debtor_account, a.iban, a.name,
           (i.principal_part+i.interest_part)::numeric,
           (case when i.due_date<current_date then 'vencido'
                 when plone27_collectable(p.debtor_account,i.principal_part+i.interest_part) then 'cobrable' else 'sin fondos' end)::text,
           ('Capital '||i.principal_part::text||' · interés '||i.interest_part::text)::text
    from plone27_plan_items i join plone27_plans p on p.id=i.plan_id join plone27_accounts a on a.id=p.debtor_account
    where i.status='pending' and p.status in('active','past_due') and i.due_date between p_desde and p_hasta
    union all
    -- Suscripciones: próximo cobro
    select p.next_due, 'Suscripción'::text, ('Suscripción '||left(p.id::text,8))::text, p.debtor_account, a.iban, a.name, p.principal::numeric,
           (case when plone27_collectable(p.debtor_account,p.principal) then 'cobrable' else 'sin fondos' end)::text,
           'Cobro periódico al beneficiario'::text
    from plone27_plans p join plone27_accounts a on a.id=p.debtor_account
    where p.kind='subscription' and p.status in('active','past_due') and p.next_due between p_desde and p_hasta
    union all
    -- Nóminas: bruto más cotización de empresa, desde la cuenta empleadora
    select c.next_pay, 'Nómina'::text, ('Contrato '||left(c.id::text,8))::text, c.employer_account, a.iban, a.name,
           (c.gross_monthly+coalesce(plone27_tax_calc(plone27_active_version('COT_EMP',c.next_pay),c.gross_monthly),0))::numeric,
           (case when plone27_collectable(c.employer_account,c.gross_monthly+coalesce(plone27_tax_calc(plone27_active_version('COT_EMP',c.next_pay),c.gross_monthly),0))
                 then 'cobrable' else 'sin fondos' end)::text,
           'Bruto más cotización de empresa'::text
    from plone27_contracts c join plone27_accounts a on a.id=c.employer_account
    where c.status='active' and c.next_pay between p_desde and p_hasta
    union all
    -- Transferencias programadas, con sus repeticiones dentro del rango (hasta 240)
    select (s.run_at+k.n*coalesce(s.recurrence,interval '0'))::date, 'Transferencia programada'::text, coalesce(s.memo,'Programada')::text,
           s.from_account, a.iban, a.name, s.amount::numeric,
           (case when plone27_collectable(s.from_account,s.amount) then 'cobrable' else 'sin fondos' end)::text,
           (case when s.recurrence is null then 'Única' else 'Recurrente' end)::text
    from plone27_scheduled s join plone27_accounts a on a.id=s.from_account
      cross join lateral generate_series(0, case when s.recurrence is null then 0 else 240 end) k(n)
    where s.status='active' and (s.run_at+k.n*coalesce(s.recurrence,interval '0'))::date between p_desde and p_hasta
    union all
    -- Cierres mensuales (el del mes en curso y el siguiente)
    select x.f, 'Cierre mensual'::text, ('Cierre de '||to_char(x.m-interval '1 month','YYYY-MM'))::text, null::uuid, null::text, null::text, null::numeric,
           (case when exists(select 1 from plone27_periodos pp where pp.periodo=(x.m-interval '1 month')::date and pp.estado='cerrado')
                 then 'cerrado' else 'programado' end)::text,
           'Liquida el IVA y los impuestos periódicos del mes anterior'::text
    from (select make_date(extract(year from ms.m)::int, extract(month from ms.m)::int,
                 (plone27_setting('dia_cierre')#>>'{}')::int) f, ms.m
          from (select date_trunc('month',current_date) m union all select date_trunc('month',current_date)+interval '1 month') ms) x
    where x.f between p_desde and p_hasta
    union all
    -- IAEP: cuota fija de cada actividad, emitida el día 1 de cada mes
    select (date_trunc('month',current_date)+interval '1 month')::date, 'IAEP mensual'::text,
           ('Actividades activas: '||count(*))::text, null::uuid, null::text, null::text, coalesce(sum(v.rate),0)::numeric,
           'estimado'::text, 'Cuota fija por categoría'::text
    from plone27_activities a join plone27_tax_rules ru on ru.code='IAEP'
      join plone27_tax_rule_versions v on v.rule_id=ru.id and v.scope_op=a.category and v.status='published'
    where a.status='active' and (date_trunc('month',current_date)+interval '1 month')::date between p_desde and p_hasta
    having count(*)>0
    union all
    -- Deudas reconocidas (incluidos intereses de demora y recargos)
    select d.due_date, 'Deuda'::text, coalesce(d.reason,'Deuda')::text, d.account_id, a.iban, a.name,
           (d.principal+d.authorized_charges-d.paid)::numeric,
           (case when d.due_date<current_date then 'vencido'
                 when plone27_collectable(d.account_id,d.principal+d.authorized_charges-d.paid) then 'cobrable' else 'sin fondos' end)::text,
           'Deuda reconocida'::text
    from plone27_debts d join plone27_accounts a on a.id=d.account_id
    where not d.disputed and d.paid<d.principal+d.authorized_charges and d.due_date between p_desde and p_hasta
    union all
    -- RBU sin reclamar: caduca en esa fecha
    select b.expires_on, 'RBU sin reclamar'::text, ('Bono semana '||b.week_start::text)::text, b.wallet_account, a.iban, a.name, b.amount::numeric,
           'disponible'::text, 'Si no se reclama, caduca'::text
    from plone27_rbu_bonuses b join plone27_accounts a on a.id=b.wallet_account
    where b.status='available' and b.expires_on between p_desde and p_hasta
    union all
    -- IVA estimado del mes en curso: base devengada por el tipo general (sin deducir compras)
    select (date_trunc('month',current_date)+interval '1 month -1 day')::date, 'IVA estimado'::text, 'Mes en curso'::text,
           null::uuid, null::text, null::text,
           round(coalesce((select sum(s.base) from plone27_sales s where s.created_at>=date_trunc('month',current_date)
                           and s.created_at<date_trunc('month',current_date)+interval '1 month'),0)
                 *coalesce((select v.rate from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id
                            where ru.code='IVA' and v.status='published' and v.scope_op is null order by v.valid_from desc limit 1),0)/100,2)::numeric,
           'estimado'::text, 'Base devengada del mes × tipo general, sin deducir compras'::text
    where (date_trunc('month',current_date)+interval '1 month -1 day')::date between p_desde and p_hasta
  ) u order by u.fecha, u.tipo;
end $$;

-- Indicadores para el panel principal
create or replace function plone27_kpis() returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'recibos_pendientes',(select count(*) from plone27_tax_receipts where status in('issued','partial')),
    'recibos_pendientes_importe',(select coalesce(sum(amount-paid_amount),0) from plone27_tax_receipts where status in('issued','partial')),
    'recibos_vencidos',(select count(*) from plone27_tax_receipts where status in('issued','partial') and due_date<current_date),
    'cuentas_activas',(select count(*) from plone27_accounts where status='active'),
    'planes_activos',(select count(*) from plone27_plans where status in('active','past_due')),
    'cuotas_pendientes_importe',(select coalesce(sum(principal_part+interest_part),0) from plone27_plan_items where status='pending'),
    'contratos_activos',(select count(*) from plone27_contracts where status='active'),
    'rbu_disponible',(select coalesce(sum(amount),0) from plone27_rbu_bonuses where status='available'),
    'hallazgos_iva_abiertos',(select count(*) from plone27_iva_findings where status in('abierto','presumido')),
    'declaraciones_retenidas',(select count(*) from plone27_declaraciones where estado='retenida'),
    'incidencias_abiertas',(select count(*) from plone27_incidents where status='open'),
    'certificacion',(plone27_certification_report()->>'estado'),
    'ultimo_cierre',(select max(periodo) from plone27_periodos where estado='cerrado'))
$$;

-- ==================== MIGRACIÓN (0016_plone27_api_bancos.sql) ====================
-- Antes de recrear las funciones de la 0016 se eliminan sus firmas: si la base ya tiene la 0017,
-- PostgreSQL no permite renombrar parámetros con CREATE OR REPLACE (error 42P13).
drop function if exists plone27_client_user(uuid,text);
drop function if exists plone27_session_open(uuid,text,text,text[],int);
drop function if exists plone27_session_check(text);
drop function if exists plone27_user_can(uuid,uuid,boolean);
drop function if exists plone27_user_accounts(uuid);
drop function if exists plone27_user_transactions(uuid,uuid,bigint,int);
drop function if exists plone27_user_receipts(uuid,uuid);
drop function if exists plone27_user_transfer(text,uuid,text,text,numeric,text);
drop function if exists plone27_client_link_account(uuid,text,uuid,text);
-- Placeta One · 0016 · API para aplicaciones de bancos con aislamiento por usuario.
-- Niveles: servidor del banco (clave + firma HMAC) → sesión de usuario (token opaco, corta) → datos solo de sus cuentas.
-- Requiere 0015. Idempotente.

alter table plone27_api_clients add column if not exists signing_secret text;   -- secreto de firma (solo servidor; nunca se devuelve)

create table if not exists plone27_api_nonces(
  client_id uuid not null references plone27_api_clients,
  nonce text not null,
  at timestamptz not null default now(),
  primary key(client_id,nonce));

create table if not exists plone27_client_origins(
  client_id uuid not null references plone27_api_clients,
  origin text not null check(origin ~ '^https?://[^/]+$'),         -- orígenes de navegador autorizados para ese cliente
  created_at timestamptz not null default now(),
  primary key(client_id,origin));


create table if not exists plone27_user_sessions(
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references plone27_api_clients,
  platform_user_id uuid not null,
  token_hash text not null unique,                                 -- solo el hash del token
  scopes text[] not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_used_at timestamptz);
create index if not exists plone27_user_sessions_user_idx on plone27_user_sessions(platform_user_id);

-- Identidad de usuario para un id externo (se crea la primera vez)


-- Valida un token: solo sesiones vigentes, no revocadas y de clientes activos
create or replace function plone27_session_check(p_hash text) returns table(client_id uuid,user_id uuid,scopes text[],rate_limit int)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.client_id,s.platform_user_id,s.scopes,c.rate_limit
    from plone27_user_sessions s join plone27_api_clients c on c.id=s.client_id
    where s.token_hash=p_hash and s.revoked_at is null and s.expires_at>now() and c.active;
end $$;

create or replace function plone27_session_revoke(p_hash text) returns boolean
language sql security definer set search_path=public as $$
  with x as (update plone27_user_sessions set revoked_at=now() where token_hash=p_hash and revoked_at is null returning 1)
  select exists(select 1 from x) $$;

-- Autorización central: el usuario pertenece a la cuenta (y puede escribir, si se pide)
create or replace function plone27_user_can(p_user uuid,p_account uuid,p_write boolean) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.account_id=p_account and m.user_id=p_user and a.status='active'
      and (not p_write or m.role in('holder','coholder'))) $$;

create or replace function plone27_user_accounts(p_user uuid) returns table(id uuid,iban text,nombre text,tipo text,rol text,saldo numeric,disponible numeric)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select a.id,a.iban,a.name,a.kind,m.role,b.booked,b.booked-b.reserved
    from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    join plone27_account_balances b on b.account_id=a.id
    where m.user_id=p_user and a.status='active' order by a.created_at;
end $$;

create or replace function plone27_user_transactions(p_user uuid,p_account uuid,p_antes bigint,p_limite int)
returns table(id bigint,fecha timestamptz,sentido text,importe numeric,tipo text,memo text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false) then raise exception 'Cuenta no accesible'; end if;
  return query select e.id,e.created_at,e.direction,e.amount,t.kind,t.memo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and (p_antes is null or e.id<p_antes)
    order by e.id desc limit least(greatest(p_limite,1),100);
end $$;

create or replace function plone27_user_receipts(p_user uuid,p_account uuid)
returns table(ref text,impuesto text,base numeric,importe numeric,pagado numeric,estado text,vence date,creado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false) then raise exception 'Cuenta no accesible'; end if;
  return query select r.ref,ru.code,r.base,r.amount,r.paid_amount,r.status,r.due_date,r.created_at
    from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
    join plone27_tax_rules ru on ru.id=v.rule_id
    where r.account_id=p_account order by r.created_at desc limit 200;
end $$;

-- Transferencia ordenada por el usuario: el origen debe ser una cuenta suya con permiso de escritura
create or replace function plone27_user_transfer(p_key text,p_user uuid,p_from_iban text,p_to_iban text,p_amount numeric,p_memo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; t uuid; begin
  select id into f from plone27_accounts where iban=p_from_iban;
  if f is null or not plone27_user_can(p_user,f,true) then raise exception 'Cuenta de origen no accesible'; end if;
  select id into t from plone27_accounts where iban=p_to_iban and status='active';
  if t is null then raise exception 'Cuenta destino no válida'; end if;
  if t=f then raise exception 'Origen y destino no pueden coincidir'; end if;
  return plone27_transfer(p_key,f,t,p_amount,coalesce(p_memo,'Transferencia'),p_user);
end $$;

-- Alta de un usuario del banco en una de sus cuentas (lo hace el servidor del banco)

-- Orígenes de navegador: los administra personal, no el banco
create or replace function plone27_client_origin_add(p_client uuid,p_origin text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  insert into plone27_client_origins(client_id,origin) values(p_client,p_origin) on conflict do nothing;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'client_origin_add','client',p_client::text,jsonb_build_object('origen',p_origin));
end $$;

-- Seguridad: las tablas nuevas no se leen desde el panel (contienen hashes y secretos de sesión)
do $$ declare t text; f text; v text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0017_plone27_dip_identificador.sql) ====================
-- Placeta One · 0017 · El DIP es el identificador del usuario.
-- Una persona = un DIP = un usuario de la plataforma en todas las entidades.
-- Cada entidad solo ve sus propias cuentas (la sesión queda ligada a la entidad del cliente).
-- Requiere 0016. Idempotente.

-- Cambian firmas y columnas devueltas: se eliminan antes de recrear (PostgreSQL no permite cambiar parámetros con OR REPLACE).
drop function if exists plone27_session_open(uuid,text,text,text[],int);
drop function if exists plone27_session_check(text);
drop function if exists plone27_user_can(uuid,uuid,boolean);
drop function if exists plone27_user_accounts(uuid);
drop function if exists plone27_user_transactions(uuid,uuid,bigint,int);
drop function if exists plone27_user_receipts(uuid,uuid);
drop function if exists plone27_user_transfer(text,uuid,text,text,numeric,text);
drop function if exists plone27_client_link_account(uuid,text,uuid,text);
drop function if exists plone27_client_user(uuid,text);
drop table if exists plone27_client_users;

-- Persona: un DIP normalizado. Es dato personal: la tabla no es legible desde el panel.
create table if not exists plone27_personas(
  id uuid primary key default gen_random_uuid(),
  dip text not null unique check(dip ~ '^[A-Z0-9]{5,20}$'),
  created_at timestamptz not null default now());

-- Sal para el hash de auditoría (aleatoria, se genera una vez por instalación)
insert into plone27_config(key,value) values('dip_pepper', replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''))
  on conflict(key) do nothing;

create or replace function plone27_normalizar_dip(p_dip text) returns text
language sql immutable as $$ select upper(regexp_replace(coalesce(p_dip,''),'[^A-Za-z0-9]','','g')) $$;

-- Hash con sal del DIP: es lo único que puede aparecer en auditoría o registros
create or replace function plone27_dip_hash(p_dip text) returns text
language sql stable security definer set search_path=public as $$
  select encode(sha256(convert_to((select value from plone27_config where key='dip_pepper')||':'||plone27_normalizar_dip(p_dip),'utf8')),'hex') $$;

-- Devuelve el identificador de la persona para un DIP (lo crea la primera vez)
create or replace function plone27_persona(p_dip text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d text:=plone27_normalizar_dip(p_dip); pid uuid; begin
  if d !~ '^[A-Z0-9]{5,20}$' then raise exception 'DIP no válido'; end if;
  insert into plone27_personas(dip) values(d) on conflict(dip) do nothing;
  select p.id into pid from plone27_personas p where p.dip=d;
  return pid; end $$;

create or replace function plone27_session_open(p_client uuid,p_dip text,p_hash text,p_scopes text[],p_ttl int) returns timestamptz
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u uuid; exp timestamptz; begin
  if p_ttl<1 or p_ttl>60 then raise exception 'TTL fuera de rango (1 a 60 minutos)'; end if;
  u:=plone27_persona(p_dip);
  exp:=now()+make_interval(mins=>p_ttl);
  insert into plone27_user_sessions(client_id,platform_user_id,token_hash,scopes,expires_at) values(p_client,u,p_hash,p_scopes,exp);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'session_open','client',p_client::text,jsonb_build_object('persona',u,'dip_hash',plone27_dip_hash(p_dip),'scopes',p_scopes,'minutos',p_ttl));
  return exp; end $$;

-- Valida un token y devuelve la entidad de la sesión (el usuario solo ve cuentas de esa entidad)
create or replace function plone27_session_check(p_hash text) returns table(client_id uuid,bank_id uuid,user_id uuid,scopes text[],rate_limit int)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.client_id,c.bank_id,s.platform_user_id,s.scopes,c.rate_limit
    from plone27_user_sessions s join plone27_api_clients c on c.id=s.client_id
    where s.token_hash=p_hash and s.revoked_at is null and s.expires_at>now() and c.active;
end $$;

-- Autorización: la cuenta es del usuario, es de la entidad de la sesión y, si se pide, puede escribir
create or replace function plone27_user_can(p_user uuid,p_account uuid,p_write boolean,p_bank uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.account_id=p_account and m.user_id=p_user and a.status='active' and a.bank_id=p_bank
      and (not p_write or m.role in('holder','coholder'))) $$;

create or replace function plone27_user_accounts(p_user uuid,p_bank uuid) returns table(id uuid,iban text,nombre text,tipo text,rol text,saldo numeric,disponible numeric)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select a.id,a.iban,a.name,a.kind,m.role,b.booked,b.booked-b.reserved
    from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    join plone27_account_balances b on b.account_id=a.id
    where m.user_id=p_user and a.status='active' and a.bank_id=p_bank order by a.created_at;
end $$;

create or replace function plone27_user_transactions(p_user uuid,p_account uuid,p_antes bigint,p_limite int,p_bank uuid)
returns table(id bigint,fecha timestamptz,sentido text,importe numeric,tipo text,memo text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select e.id,e.created_at,e.direction,e.amount,t.kind,t.memo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and (p_antes is null or e.id<p_antes)
    order by e.id desc limit least(greatest(p_limite,1),100);
end $$;

create or replace function plone27_user_receipts(p_user uuid,p_account uuid,p_bank uuid)
returns table(ref text,impuesto text,base numeric,importe numeric,pagado numeric,estado text,vence date,creado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select r.ref,ru.code,r.base,r.amount,r.paid_amount,r.status,r.due_date,r.created_at
    from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
    join plone27_tax_rules ru on ru.id=v.rule_id
    where r.account_id=p_account order by r.created_at desc limit 200;
end $$;

create or replace function plone27_user_transfer(p_key text,p_user uuid,p_from_iban text,p_to_iban text,p_amount numeric,p_memo text,p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; t uuid; begin
  select id into f from plone27_accounts where iban=p_from_iban;
  if f is null or not plone27_user_can(p_user,f,true,p_bank) then raise exception 'Cuenta de origen no accesible'; end if;
  select id into t from plone27_accounts where iban=p_to_iban and status='active';
  if t is null then raise exception 'Cuenta destino no válida'; end if;
  if t=f then raise exception 'Origen y destino no pueden coincidir'; end if;
  return plone27_transfer(p_key,f,t,p_amount,coalesce(p_memo,'Transferencia'),p_user);
end $$;

-- Alta de un usuario (DIP) en una cuenta de la entidad del cliente
create or replace function plone27_client_link_account(p_client uuid,p_dip text,p_account uuid,p_role text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u uuid; bk uuid; begin
  select bank_id into bk from plone27_api_clients where id=p_client;
  if not exists(select 1 from plone27_accounts where id=p_account and bank_id=bk) then raise exception 'La cuenta no pertenece a la entidad del cliente'; end if;
  if p_role not in('holder','coholder','authorized') then raise exception 'Rol no válido'; end if;
  u:=plone27_persona(p_dip);
  insert into plone27_account_members(account_id,user_id,role) values(p_account,u,p_role)
    on conflict(account_id,user_id) do update set role=excluded.role;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'client_link','account',p_account::text,jsonb_build_object('cliente',p_client,'dip_hash',plone27_dip_hash(p_dip),'rol',p_role));
  return u; end $$;

-- Seguridad: el DIP y los tokens no se leen desde el panel
do $$ declare t text; f text; v text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces','plone27_personas') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0018_plone27_api_banca_completa.sql) ====================
-- Placeta One · 0018 · API completa de banca online (ficha de cuenta, programadas, certificados, RBU,
-- previsión personal, planes, búsqueda de destinatarios y búsqueda por DIP para el banco).
-- Requiere 0017. Idempotente. Todas las funciones de usuario comprueban pertenencia y entidad.

-- Idempotencia para las transferencias programadas (un reintento no crea otra programación)
alter table plone27_scheduled add column if not exists clave_idem text unique;

-- Ficha de una cuenta del usuario
create or replace function plone27_user_account_detail(p_user uuid,p_account uuid,p_bank uuid)
returns table(iban text,nombre text,tipo text,estado text,rol text,saldo numeric,reservado numeric,disponible numeric,limite_diario numeric,descubierto boolean)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select a.iban,a.name,a.kind,a.status,
      (select m.role from plone27_account_members m where m.account_id=a.id and m.user_id=p_user limit 1),
      b.booked,b.reserved,b.booked-b.reserved,a.daily_limit,a.allow_negative
    from plone27_accounts a join plone27_account_balances b on b.account_id=a.id where a.id=p_account;
end $$;

-- Transferencia programada (única o periódica). Solo desde cuentas del usuario con permiso de escritura.
create or replace function plone27_user_scheduled_create(p_user uuid,p_bank uuid,p_from_iban text,p_to_iban text,p_amount numeric,
  p_run_at timestamptz,p_recurrence interval,p_memo text,p_clave text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; t uuid; sid uuid; begin
  select a.id into f from plone27_accounts a where a.iban=p_from_iban;
  if f is null or not plone27_user_can(p_user,f,true,p_bank) then raise exception 'Cuenta de origen no accesible'; end if;
  select a.id into t from plone27_accounts a where a.iban=p_to_iban and a.status='active';
  if t is null then raise exception 'Cuenta destino no válida'; end if;
  if t=f then raise exception 'Origen y destino no pueden coincidir'; end if;
  if p_run_at < now() - interval '1 minute' then raise exception 'La fecha debe ser futura'; end if;
  if p_recurrence is not null and p_recurrence < interval '1 day' then raise exception 'La periodicidad mínima es de un día'; end if;
  insert into plone27_scheduled(from_account,to_account,amount,run_at,recurrence,memo,clave_idem)
    values(f,t,p_amount,p_run_at,p_recurrence,coalesce(p_memo,'Transferencia programada'),p_clave)
    on conflict(clave_idem) do update set clave_idem=excluded.clave_idem
    returning plone27_scheduled.id into sid;
  return sid; end $$;

create or replace function plone27_user_scheduled_list(p_user uuid,p_bank uuid)
returns table(id uuid,origen text,destino text,importe numeric,proxima timestamptz,periodicidad interval,estado text,concepto text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.id,fa.iban,ta.iban,s.amount,s.run_at,s.recurrence,s.status,s.memo
    from plone27_scheduled s join plone27_accounts fa on fa.id=s.from_account join plone27_accounts ta on ta.id=s.to_account
    where s.status='active' and plone27_user_can(p_user,s.from_account,false,p_bank)
    order by s.run_at;
end $$;

create or replace function plone27_user_scheduled_cancel(p_user uuid,p_bank uuid,p_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; begin
  select s.from_account into f from plone27_scheduled s where s.id=p_id and s.status='active';
  if f is null or not plone27_user_can(p_user,f,true,p_bank) then raise exception 'Programación no encontrada'; end if;
  update plone27_scheduled set status='cancelled' where id=p_id;
  return true; end $$;

-- Certificado de un recibo propio (el recibo debe ser de una cuenta del usuario en su entidad)
create or replace function plone27_user_receipt_certificate(p_user uuid,p_bank uuid,p_ref text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rid uuid; acc uuid; begin
  select r.id,r.account_id into rid,acc from plone27_tax_receipts r where r.ref=p_ref;
  if rid is null or not plone27_user_can(p_user,acc,false,p_bank) then raise exception 'Recibo no encontrado'; end if;
  return plone27_receipt_certificate(rid); end $$;

-- RBU del usuario en su entidad
create or replace function plone27_user_rbu_list(p_user uuid,p_bank uuid)
returns table(id uuid,semana date,importe numeric,estado text,caduca date,cartera text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select b.id,b.week_start,b.amount,b.status,b.expires_on,wa.iban
    from plone27_rbu_bonuses b join plone27_accounts wa on wa.id=b.wallet_account
    where b.owner_user=p_user and wa.bank_id=p_bank order by b.week_start desc limit 52;
end $$;

create or replace function plone27_user_rbu_claim(p_user uuid,p_bank uuid,p_bonus uuid,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w uuid; begin
  select b.wallet_account into w from plone27_rbu_bonuses b join plone27_accounts a on a.id=b.wallet_account
    where b.id=p_bonus and a.bank_id=p_bank and b.owner_user=p_user;
  if w is null then raise exception 'Bono no encontrado'; end if;
  return plone27_rbu_claim(p_bonus,p_user,p_key); end $$;

-- Previsión de los movimientos del usuario (solo de sus cuentas)
create or replace function plone27_user_previsiones(p_user uuid,p_bank uuid,p_desde date,p_hasta date)
returns table(fecha date,tipo text,referencia text,iban text,importe numeric,estado text,detalle text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select p.fecha,p.tipo,p.referencia,p.iban,p.importe,p.estado,p.detalle
    from plone27_previsiones(p_desde,p_hasta) p
    where p.cuenta in (select ua.id from plone27_user_accounts(p_user,p_bank) ua)
    order by p.fecha,p.tipo;
end $$;

-- Planes a plazos y suscripciones en los que el usuario es deudor (en su entidad)
create or replace function plone27_user_plans(p_user uuid,p_bank uuid)
returns table(id uuid,tipo text,cuenta text,capital numeric,tasa_anual numeric,cuotas int,estado text,proxima date)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select p.id,p.kind,a.iban,p.principal,p.annual_rate_pct,p.installments,p.status,p.next_due
    from plone27_plans p join plone27_accounts a on a.id=p.debtor_account
    where a.bank_id=p_bank and plone27_user_can(p_user,p.debtor_account,false,p_bank)
    order by p.created_at desc;
end $$;

-- Búsqueda de destinatario por IBAN: no revela el tipo de cuenta ni más datos que el titular abreviado
create or replace function plone27_lookup_iban(p_iban text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare r record; begin
  select a.name,b.code into r from plone27_accounts a left join plone27_banks b on b.id=a.bank_id
    where a.iban=p_iban and a.status='active';
  if r is null then return jsonb_build_object('existe',false); end if;
  return jsonb_build_object('existe',true,'entidad',r.code,'titular',left(coalesce(r.name,''),2)||'***'); end $$;

-- Búsqueda por DIP para el banco (servidor). Solo devuelve cuentas de SU entidad.
-- La respuesta es igual tanto si el DIP no existe como si no tiene cuentas en ese banco.
create or replace function plone27_bk_buscar_dip(p_client uuid,p_dip text)
returns table(iban text,nombre text,tipo text,rol text,estado text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d text:=plone27_normalizar_dip(p_dip); bk uuid; pid uuid; begin
  select c.bank_id into bk from plone27_api_clients c where c.id=p_client;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'bk_buscar_dip','client',p_client::text,jsonb_build_object('dip_hash',plone27_dip_hash(d)));
  if d !~ '^[A-Z0-9]{5,20}$' then return; end if;
  select p.id into pid from plone27_personas p where p.dip=d;
  if pid is null then return; end if;
  return query select a.iban,a.name,a.kind,m.role,a.status
    from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.user_id=pid and a.bank_id=bk order by a.created_at;
end $$;

-- Seguridad (mismo patrón; el DIP y los tokens no se leen desde el panel)
do $$ declare t text; f text; v text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces','plone27_personas') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0019_plone27_banca_completa_2.sql) ====================
-- Placeta One · 0019 · Banca online completa (segunda fase): beneficiarios, tarjetas del usuario,
-- notificaciones, extracto, apertura de cuentas, solicitudes y gestión de sesiones.
-- Requiere 0018. Idempotente. Todo comprueba pertenencia de la cuenta y entidad de la sesión.

-- ========== TABLAS ==========
create table if not exists plone27_beneficiarios(
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references plone27_personas,
  bank_id uuid not null references plone27_banks,
  alias text not null check(length(alias) between 1 and 60),
  iban text not null,
  created_at timestamptz not null default now(),
  unique(persona,bank_id,iban));

create table if not exists plone27_notificaciones(
  id bigint generated always as identity primary key,
  persona uuid not null references plone27_personas,
  bank_id uuid not null references plone27_banks,
  tipo text not null,
  texto text not null,
  creada timestamptz not null default now(),
  leida timestamptz);
create index if not exists plone27_notif_persona_idx on plone27_notificaciones(persona,bank_id,id);

create table if not exists plone27_solicitudes(
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references plone27_personas,
  bank_id uuid not null references plone27_banks,
  tipo text not null check(tipo in('prestamo','cuenta')),
  importe numeric(18,2) not null default 0 check(importe>=0),
  cuotas int,
  motivo text,
  estado text not null default 'pendiente' check(estado in('pendiente','aprobada','rechazada')),
  clave_idem text unique,
  creada timestamptz not null default now(),
  resuelta timestamptz,
  resuelta_por uuid);

-- ========== NOTIFICACIONES AUTOMÁTICAS: cada movimiento de una cuenta avisa a sus titulares ==========
create or replace function plone27_notify_ledger() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare bk uuid; ib text; begin
  select a.bank_id,a.iban into bk,ib from plone27_accounts a where a.id=new.account_id;
  if bk is null then return null; end if;
  insert into plone27_notificaciones(persona,bank_id,tipo,texto)
    select m.user_id,bk,
      case when new.direction='credit' then 'ingreso' else 'cargo' end,
      case when new.direction='credit' then 'Has recibido '||new.amount::text||' Pz en '||ib
           else 'Se han cargado '||new.amount::text||' Pz en '||ib end
    from plone27_account_members m join plone27_personas p on p.id=m.user_id
    where m.account_id=new.account_id and m.role in('holder','coholder');   -- solo personas: un usuario del personal nunca bloquea un apunte
  return null; end $$;
drop trigger if exists t_notify_ledger on plone27_ledger_entries;
drop trigger if exists t_notify_ledger on plone27_ledger_entries;
create trigger t_notify_ledger after insert on plone27_ledger_entries for each row execute function plone27_notify_ledger();

-- ========== BENEFICIARIOS ==========
create or replace function plone27_user_beneficiary_add(p_user uuid,p_bank uuid,p_alias text,p_iban text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare bid uuid; begin
  if coalesce(length(p_alias),0) not between 1 and 60 then raise exception 'Alias entre 1 y 60 caracteres'; end if;
  if not exists(select 1 from plone27_accounts where iban=p_iban and status='active') then raise exception 'IBAN no válido'; end if;
  insert into plone27_beneficiarios(persona,bank_id,alias,iban) values(p_user,p_bank,p_alias,p_iban)
    on conflict(persona,bank_id,iban) do update set alias=excluded.alias
    returning plone27_beneficiarios.id into bid;
  return bid; end $$;

create or replace function plone27_user_beneficiaries(p_user uuid,p_bank uuid)
returns table(id uuid,alias text,iban text,creado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select b.id,b.alias,b.iban,b.created_at from plone27_beneficiarios b
    where b.persona=p_user and b.bank_id=p_bank order by b.alias;
end $$;

create or replace function plone27_user_beneficiary_delete(p_user uuid,p_bank uuid,p_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(delete from plone27_beneficiarios where id=p_id and persona=p_user and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Beneficiario no encontrado'; end if;
  return true; end $$;

-- ========== TARJETAS DEL USUARIO (consulta y suspensión temporal) ==========
create or replace function plone27_user_cards(p_user uuid,p_bank uuid,p_iban text)
returns table(ref text,tipo text,ultimos4 text,caduca date,estado text,limite numeric)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  select a.id into acc from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if acc is null or not plone27_user_can(p_user,acc,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select c.card_ref,c.kind,c.last4,c.expires,c.status,c.credit_limit from plone27_cards c where c.account_id=acc;
end $$;

-- El usuario solo puede suspender ('suspended') o reactivar ('active') sus tarjetas. Bloqueo y cierre los hace el banco.
create or replace function plone27_user_card_state(p_user uuid,p_bank uuid,p_ref text,p_estado text) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; acc uuid; st text; begin
  if p_estado not in('active','suspended') then raise exception 'Estado no permitido: solo activar o suspender'; end if;
  select c.id,c.account_id,c.status into cid,acc,st from plone27_cards c where c.card_ref=p_ref for update;
  if cid is null or not plone27_user_can(p_user,acc,true,p_bank) then raise exception 'Tarjeta no encontrada'; end if;
  if st not in('active','suspended') then raise exception 'La tarjeta no se puede cambiar en su estado actual'; end if;
  update plone27_cards set status=p_estado where id=cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'card_state','card',cid::text,jsonb_build_object('persona',p_user,'estado',p_estado));
  return p_estado; end $$;

-- ========== NOTIFICACIONES DEL USUARIO ==========
create or replace function plone27_user_notifications(p_user uuid,p_bank uuid,p_solo_nuevas boolean,p_limite int)
returns table(id bigint,tipo text,texto text,creada timestamptz,leida boolean)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select n.id,n.tipo,n.texto,n.creada,(n.leida is not null)
    from plone27_notificaciones n
    where n.persona=p_user and n.bank_id=p_bank and (not coalesce(p_solo_nuevas,false) or n.leida is null)
    order by n.id desc limit least(greatest(coalesce(p_limite,50),1),200);
end $$;

create or replace function plone27_user_notifications_read(p_user uuid,p_bank uuid,p_ids bigint[]) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_notificaciones set leida=now()
            where persona=p_user and bank_id=p_bank and leida is null and (p_ids is null or id=any(p_ids)) returning 1)
  select count(*) into n from x;
  return n; end $$;

-- ========== EXTRACTO: saldo inicial, movimientos del periodo y saldo final ==========
create or replace function plone27_user_statement(p_user uuid,p_bank uuid,p_account uuid,p_desde date,p_hasta date) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ap numeric; mov jsonb; efecto_periodo numeric; begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  if p_hasta<p_desde or (p_hasta-p_desde)>366 then raise exception 'Periodo no válido (máximo 366 días)'; end if;
  select coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) into ap
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and t.created_at<p_desde::timestamptz;
  select coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) into efecto_periodo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and t.created_at>=p_desde::timestamptz and t.created_at<(p_hasta+1)::timestamptz;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.fecha,x.id),'[]'::jsonb) into mov from (
    select e.id,t.created_at fecha,e.direction sentido,e.amount importe,t.kind tipo,t.memo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and t.created_at>=p_desde::timestamptz and t.created_at<(p_hasta+1)::timestamptz) x;
  return jsonb_build_object('desde',p_desde,'hasta',p_hasta,'saldo_inicial',ap,'movimientos',mov,
    'saldo_final',ap+efecto_periodo);
end $$;

-- ========== APERTURA DE CUENTA PERSONAL POR EL USUARIO (máximo 3 por entidad) ==========
create or replace function plone27_user_open_account(p_user uuid,p_bank uuid,p_nombre text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; r jsonb; aid uuid; begin
  if coalesce(length(p_nombre),0) not between 3 and 60 then raise exception 'Nombre de la cuenta: entre 3 y 60 caracteres'; end if;
  select count(*) into n from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.user_id=p_user and a.bank_id=p_bank and a.kind='personal' and a.status='active' and m.role='holder';
  if n>=3 then raise exception 'Ya tiene el máximo de cuentas personales en esta entidad'; end if;
  r:=plone27_open_account(p_bank,'personal',p_nombre,p_user,null);
  aid:=(r->>'id')::uuid;
  insert into plone27_account_members(account_id,user_id,role) values(aid,p_user,'holder') on conflict(account_id,user_id) do nothing;
  return aid; end $$;

-- ========== SOLICITUDES (préstamo o cuenta): quedan pendientes hasta que el personal las resuelva ==========
create or replace function plone27_user_request_create(p_user uuid,p_bank uuid,p_tipo text,p_importe numeric,p_cuotas int,p_motivo text,p_clave text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare sid uuid; begin
  if p_tipo not in('prestamo','cuenta') then raise exception 'Tipo de solicitud no válido'; end if;
  if p_tipo='prestamo' and (p_importe is null or p_importe<=0 or p_importe>50000) then raise exception 'Importe de préstamo entre 0 y 50.000 Pz'; end if;
  if p_tipo='prestamo' and (p_cuotas is null or p_cuotas<1 or p_cuotas>120) then raise exception 'Cuotas entre 1 y 120'; end if;
  if coalesce(length(p_motivo),0)>500 then raise exception 'Motivo demasiado largo (máximo 500)'; end if;
  insert into plone27_solicitudes(persona,bank_id,tipo,importe,cuotas,motivo,clave_idem)
    values(p_user,p_bank,p_tipo,coalesce(p_importe,0),p_cuotas,p_motivo,p_clave)
    on conflict(clave_idem) do update set clave_idem=excluded.clave_idem
    returning plone27_solicitudes.id into sid;
  return sid; end $$;

create or replace function plone27_user_requests(p_user uuid,p_bank uuid)
returns table(id uuid,tipo text,importe numeric,cuotas int,estado text,creada timestamptz,resuelta timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.id,s.tipo,s.importe,s.cuotas,s.estado,s.creada,s.resuelta
    from plone27_solicitudes s where s.persona=p_user and s.bank_id=p_bank order by s.creada desc limit 100;
end $$;

-- ========== SESIONES DEL USUARIO ==========
create or replace function plone27_user_sessions_list(p_user uuid)
returns table(id uuid,cliente text,creada timestamptz,expira timestamptz,revocada boolean,permisos text[])
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.id,c.name,s.created_at,s.expires_at,(s.revoked_at is not null),s.scopes
    from plone27_user_sessions s join plone27_api_clients c on c.id=s.client_id
    where s.platform_user_id=p_user order by s.created_at desc limit 50;
end $$;

-- Cierra todas las sesiones del usuario excepto la actual (la que hace la petición)
create or replace function plone27_user_sessions_revoke_others(p_user uuid,p_hash_actual text) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_user_sessions set revoked_at=now()
            where platform_user_id=p_user and revoked_at is null and expires_at>now() and token_hash<>p_hash_actual returning 1)
  select count(*) into n from x;
  return n; end $$;

-- Seguridad (mismo patrón; no legibles desde el panel)
do $$ declare t text; f text; v text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces','plone27_personas') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== MIGRACIÓN (0020_plone27_api_mantenimiento.sql) ====================
-- Placeta One · 0020 · Mantenimiento de la API de bancos y gestión de orígenes de navegador desde el panel.
-- Requiere 0019. Idempotente.

-- Quitar un origen de navegador de un cliente
create or replace function plone27_client_origin_remove(p_client uuid,p_origin text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  delete from plone27_client_origins where client_id=p_client and origin=p_origin;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'client_origin_remove','client',p_client::text,jsonb_build_object('origen',p_origin));
end $$;

-- Limpieza diaria: nonces de más de un día (la ventana de firma es de 5 minutos)
-- y sesiones caducadas hace más de 30 días. Las sesiones recientes se conservan para auditoría.
create or replace function plone27_limpiar_api() returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n1 int; n2 int; begin
  with x as(delete from plone27_api_nonces where at<now()-interval '1 day' returning 1) select count(*) into n1 from x;
  with y as(delete from plone27_user_sessions where expires_at<now()-interval '30 days' returning 1) select count(*) into n2 from y;
  return jsonb_build_object('nonces_borrados',n1,'sesiones_borradas',n2); end $$;

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

-- ==================== MIGRACIÓN (0021_plone27_cors_origenes.sql) ====================
-- Placeta One · 0021 · Orígenes de navegador (CORS) gestionados por el banco, con aprobación del personal.
-- Requiere 0020. Idempotente.

alter table plone27_client_origins add column if not exists estado text not null default 'aprobado'
  check(estado in('pendiente','aprobado','rechazado'));   -- los orígenes existentes quedan aprobados
alter table plone27_client_origins add column if not exists entorno text not null default 'produccion'
  check(entorno in('produccion','pruebas'));
alter table plone27_client_origins add column if not exists solicitado_at timestamptz not null default now();
alter table plone27_client_origins add column if not exists aprobado_por uuid;
alter table plone27_client_origins add column if not exists aprobado_at timestamptz;

-- Formato permitido. Producción: https://dominio[:puerto], sin ruta, sin comodines.
-- Pruebas: además http://localhost[:puerto].
create or replace function plone27_origen_valido(p_origin text,p_entorno text) returns boolean
language sql immutable as $$
  select case when p_entorno='pruebas'
    then p_origin ~ '^https://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]{1,5})?$' or p_origin ~ '^http://localhost(:[0-9]{1,5})?$'
    else p_origin ~ '^https://[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:[0-9]{1,5})?$'
  end $$;

-- El banco solicita un origen: queda pendiente. Máximo 10 por cliente.
create or replace function plone27_client_origin_request(p_client uuid,p_origin text,p_entorno text) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare o text:=lower(trim(p_origin)); n int; est text; begin
  if p_entorno not in('produccion','pruebas') then raise exception 'Entorno no válido'; end if;
  if not plone27_origen_valido(o,p_entorno) then raise exception 'Origen no válido: https://dominio[:puerto], sin ruta ni comodines'; end if;
  select count(*) into n from plone27_client_origins where client_id=p_client and estado<>'rechazado';
  if n>=10 then raise exception 'Máximo 10 orígenes por cliente'; end if;
  insert into plone27_client_origins(client_id,origin,estado,entorno,solicitado_at)
    values(p_client,o,'pendiente',p_entorno,now())
    on conflict(client_id,origin) do update
      set estado=case when plone27_client_origins.estado='rechazado' then 'pendiente' else plone27_client_origins.estado end,
          entorno=excluded.entorno
    returning plone27_client_origins.estado into est;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'client_origin_request','client',p_client::text,jsonb_build_object('origen',o,'entorno',p_entorno,'estado',est));
  return est; end $$;

-- El personal aprueba o rechaza
create or replace function plone27_client_origin_decide(p_client uuid,p_origin text,p_decision text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_decision not in('aprobado','rechazado') then raise exception 'Decisión no válida'; end if;
  if p_actor is null then raise exception 'La decisión requiere un aprobador'; end if;
  update plone27_client_origins set estado=p_decision,aprobado_por=p_actor,aprobado_at=now()
    where client_id=p_client and origin=lower(trim(p_origin));
  if not found then raise exception 'Origen no encontrado'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'client_origin_decide','client',p_client::text,jsonb_build_object('origen',lower(trim(p_origin)),'decision',p_decision));
end $$;

-- Lista de orígenes de un cliente (lo consulta el propio banco)
create or replace function plone27_client_origins_list(p_client uuid)
returns table(origin text,estado text,entorno text,solicitado timestamptz,aprobado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select o.origin,o.estado,o.entorno,o.solicitado_at,o.aprobado_at
    from plone27_client_origins o where o.client_id=p_client order by o.origin;
end $$;

-- ¿Puede este origen llamar a la API? Solo si está aprobado y su cliente activo.
-- Con p_client se comprueba que el origen pertenece a ese cliente concreto.
create or replace function plone27_origen_permitido(p_origin text,p_client uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_client_origins o join plone27_api_clients c on c.id=o.client_id
    where o.origin=lower(p_origin) and o.estado='aprobado' and c.active
      and (p_client is null or o.client_id=p_client)) $$;

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

-- ==================== MIGRACIÓN (0022_plone27_catalogo_disenos.sql) ====================
-- Placeta One · 0022 · Catálogo de diseños de tarjeta: código, banco, rareza, imagen/GIF, stock y publicación en API.
-- Requiere 0021. Idempotente.

create sequence if not exists plone27_design_codigo_seq;
alter table plone27_card_designs add column if not exists codigo text unique
  default ('DIS-'||lpad(nextval('plone27_design_codigo_seq')::text,5,'0'));   -- identificador comercial estable
alter table plone27_card_designs add column if not exists bank_id uuid references plone27_banks;   -- null = catálogo general
alter table plone27_card_designs add column if not exists rareza text not null default 'comun'
  check(rareza in('comun','rara','epica','legendaria'));
alter table plone27_card_designs add column if not exists descripcion text check(length(descripcion)<=500);
alter table plone27_card_designs add column if not exists imagen_url text check(imagen_url is null or imagen_url ~ '^https://[^\s]+$');
alter table plone27_card_designs add column if not exists animacion_url text check(animacion_url is null or animacion_url ~ '^https://[^\s]+$');
alter table plone27_card_designs add column if not exists stock int check(stock is null or stock>=0);   -- null = ilimitado
alter table plone27_card_designs add column if not exists vendidos int not null default 0 check(vendidos>=0);
alter table plone27_card_designs add column if not exists publicado_api boolean not null default false;

-- Restricción de stock. El generador de instalación la hace idempotente por sí mismo: no envolver en DO.
do $$ begin alter table plone27_card_designs add constraint plone27_design_stock_ck check(stock is null or vendidos<=stock) not valid; exception when duplicate_object then null; end $$;

-- Compra de un diseño: comprueba estado, banco y stock; descuenta una unidad solo en la primera compra
-- (un reintento con la misma clave no vuelve a restar).
create or replace function plone27_design_buy(p_key text,p_design uuid,p_account uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_card_designs; tx uuid; t numeric; ab uuid; ya boolean; ins int; begin
  select * into d from plone27_card_designs where id=p_design for update;
  if d.id is null then raise exception 'Diseño no encontrado'; end if;
  if d.status<>'approved' or not d.publicado_api then raise exception 'Diseño no disponible'; end if;
  select a.bank_id into ab from plone27_accounts a where a.id=p_account;
  if d.bank_id is not null and d.bank_id<>ab then raise exception 'Diseño no disponible en tu entidad'; end if;
  select exists(select 1 from plone27_design_purchases p where p.design_id=p_design and p.account_id=p_account) into ya;
  if not ya and d.stock is not null and d.vendidos>=d.stock then raise exception 'Sin stock'; end if;
  t:=d.price+d.license_fee;
  if t>0 then tx:=plone27_transfer(p_key,p_account,d.revenue_account,t,'Diseño '||d.name,p_actor); end if;
  insert into plone27_design_purchases(design_id,account_id,tx) values(p_design,p_account,tx) on conflict do nothing;
  get diagnostics ins = row_count;
  if ins>0 then update plone27_card_designs set vendidos=vendidos+1 where id=p_design; end if;
  return tx;
end $$;

-- Catálogo para un banco: diseños aprobados, publicados en API, de su entidad o generales, con stock disponible
create or replace function plone27_catalogo_disenos(p_bank uuid)
returns table(codigo text,nombre text,nivel text,rareza text,precio numeric,licencia numeric,descripcion text,
              imagen_url text,animacion_url text,stock_disponible int,vendidos int)
language sql stable security definer set search_path=public as $$
  select d.codigo,d.name,d.tier,d.rareza,d.price,d.license_fee,d.descripcion,d.imagen_url,d.animacion_url,
         case when d.stock is null then null else (d.stock-d.vendidos)::int end,
         d.vendidos
  from plone27_card_designs d
  where d.status='approved' and d.publicado_api and (d.bank_id is null or d.bank_id=p_bank)
    and (d.stock is null or d.vendidos<d.stock)
  order by d.name
$$;

-- Catálogo para un usuario concreto: añade si ya tiene el diseño en alguna de sus cuentas
create or replace function plone27_user_catalogo(p_user uuid,p_bank uuid)
returns table(codigo text,nombre text,nivel text,rareza text,precio numeric,licencia numeric,descripcion text,
              imagen_url text,animacion_url text,stock_disponible int,ya_adquirido boolean)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
    select c.codigo,c.nombre,c.nivel,c.rareza,c.precio,c.licencia,c.descripcion,c.imagen_url,c.animacion_url,c.stock_disponible,
           exists(select 1 from plone27_design_purchases p
                  join plone27_account_members m on m.account_id=p.account_id
                  join plone27_card_designs dd on dd.id=p.design_id
                  where dd.codigo=c.codigo and m.user_id=p_user)
    from plone27_catalogo_disenos(p_bank) c;
end $$;

-- Compra de un diseño por un usuario, desde una cuenta propia con permiso de escritura
create or replace function plone27_user_diseno_comprar(p_user uuid,p_bank uuid,p_codigo text,p_iban text,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; did uuid; begin
  select a.id into acc from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if acc is null or not plone27_user_can(p_user,acc,true,p_bank) then raise exception 'Cuenta no accesible'; end if;
  select d.id into did from plone27_card_designs d where d.codigo=p_codigo and (d.bank_id is null or d.bank_id=p_bank);
  if did is null then raise exception 'Diseño no encontrado'; end if;
  return plone27_design_buy(p_key, did, acc, p_user);
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

-- ==================== MIGRACIÓN (0023_plone27_pasarela_y_pagos_bancos.sql) ====================
-- Placeta One · 0023 · Pasarela de pago para webs de bancos (popup con código de verificación),
-- cargos de tarjeta por API con idempotencia, y lectura de nóminas y planes por entidad.
-- Requiere 0022. Idempotente.

-- ---------- Identidad visual de cada banco ----------
alter table plone27_banks add column if not exists logo_url text check(logo_url is null or logo_url ~ '^https://[^\s]+$');
alter table plone27_banks add column if not exists color_principal text check(color_principal is null or color_principal ~ '^#[0-9A-Fa-f]{6}$');

-- ---------- Cargos de tarjeta: clave de idempotencia ----------
alter table plone27_card_charges add column if not exists idem_key text unique;

-- ---------- Hash de tokens y códigos (nunca se guardan en claro) ----------
create or replace function plone27_sha(p text) returns text language sql immutable as $$
  select encode(sha256(convert_to(p,'utf8')),'hex') $$;

-- ---------- Pagos de pasarela ----------
create table if not exists plone27_checkouts(
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  bank_id uuid not null references plone27_banks,
  client_id uuid not null references plone27_api_clients,
  origen_banco text not null check(origen_banco ~ '^https://[^\s]+$' or origen_banco ~ '^http://localhost(:[0-9]+)?$'),
  client_ref text not null check(length(client_ref) between 1 and 80),
  pagador_persona uuid not null references plone27_personas,
  pagador_cuenta uuid not null references plone27_accounts,
  cuenta_destino uuid not null references plone27_accounts,
  importe numeric(18,2) not null check(importe>0),
  concepto text not null check(length(concepto) between 1 and 120),
  codigo_hash text not null,
  codigo_expira timestamptz not null,
  intentos int not null default 0 check(intentos between 0 and 10),
  estado text not null default 'pendiente' check(estado in('pendiente','pagado','fallido','cancelado','caducado')),
  tx uuid,
  expira_at timestamptz not null,
  creada timestamptz not null default now(),
  resuelta timestamptz,
  unique(client_id,client_ref));

-- Crea un pago. El código de verificación sale por webhook (checkout.codigo) hacia el banco.
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; cuenta uuid; destino uuid; cid uuid; caduca timestamptz; mins int := coalesce(p_minutos,15); begin
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>50000 then raise exception 'Importe entre 0,01 y 50.000 Pz'; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if coalesce(length(p_codigo),0)<>6 then raise exception 'Código de verificación no válido'; end if;
  pid := plone27_persona(p_dip);
  select a.id into cuenta from plone27_accounts a where a.iban=p_iban_pagador and a.bank_id=p_bank;
  if cuenta is null or not plone27_user_can(pid,cuenta,true,p_bank) then raise exception 'Cuenta del pagador no accesible'; end if;
  select a.id into destino from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  caduca := now()+make_interval(mins => mins);
  insert into plone27_checkouts(token_hash,bank_id,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
                                importe,concepto,codigo_hash,codigo_expira,expira_at)
    values(plone27_sha(p_token),p_bank,p_client,lower(p_origen),p_client_ref,pid,cuenta,destino,
           p_importe,p_concepto,plone27_sha(p_codigo),caduca,caduca)
    returning id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.codigo',array[p_bank],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'codigo',p_codigo,'importe',p_importe,'concepto',p_concepto,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca);
end $$;

-- Estado público del pago para la ventana emergente (sin datos internos)
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'intentos_restantes',greatest(0,3-c.intentos),
    'origen',c.origen_banco,'banco',jsonb_build_object('nombre',b.name,'logo',b.logo_url,'color',b.color_principal),
    'comercio',cl.name)
  from plone27_checkouts c join plone27_banks b on b.id=c.bank_id join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

-- Confirmación con el código. Tres intentos. La transferencia es idempotente por el id del pago.
create or replace function plone27_checkout_confirm(p_token text,p_codigo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; tx uuid; begin
  select * into c from plone27_checkouts where token_hash=plone27_sha(p_token) for update;
  if c.id is null then return jsonb_build_object('ok',false,'error','Pago no encontrado'); end if;
  if c.estado<>'pendiente' then return jsonb_build_object('ok',false,'error','Este pago ya no está pendiente','estado',c.estado); end if;
  if c.expira_at<now() then
    update plone27_checkouts set estado='caducado',resuelta=now() where id=c.id;
    return jsonb_build_object('ok',false,'error','El pago ha caducado','estado','caducado');
  end if;
  if c.codigo_hash<>plone27_sha(coalesce(p_codigo,'')) then
    update plone27_checkouts set intentos=intentos+1,
      estado=case when intentos+1>=3 then 'fallido' else estado end,
      resuelta=case when intentos+1>=3 then now() else resuelta end
      where id=c.id;
    return jsonb_build_object('ok',false,'error','Código incorrecto',
      'intentos_restantes',greatest(0,2-c.intentos),
      'estado',case when c.intentos+1>=3 then 'fallido' else 'pendiente' end);
  end if;
  begin
    tx:=plone27_transfer('checkout:'||c.id::text,c.pagador_cuenta,c.cuenta_destino,c.importe,c.concepto,null);
  exception when others then
    return jsonb_build_object('ok',false,'error',sqlerrm,'estado','pendiente');
  end;
  update plone27_checkouts set estado='pagado',tx=tx,resuelta=now() where id=c.id;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.pagado',array[c.bank_id],
    jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'importe',c.importe,'transaccion',tx));
  return jsonb_build_object('ok',true,'transaccion',tx,'estado','pagado');
end $$;

create or replace function plone27_checkout_cancel(p_token text) returns boolean
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_checkouts set estado='cancelado',resuelta=now()
            where token_hash=plone27_sha(p_token) and estado='pendiente' returning 1)
  select count(*) into n from x;
  if n>0 then
    insert into plone27_outbox(event,bank_ids,payload)
      select 'checkout.cancelado',array[c.bank_id],jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref)
      from plone27_checkouts c where c.token_hash=plone27_sha(p_token);
  end if;
  return n>0; end $$;

-- Consulta del banco: sin código, sin token
create or replace function plone27_bk_checkout_get(p_client uuid,p_id uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',c.id,'client_ref',c.client_ref,
    'estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'transaccion',c.tx,'creado',c.creada,'resuelto',c.resuelta,'intentos',c.intentos)
  from plone27_checkouts c where c.id=p_id and c.client_id=p_client $$;

-- ---------- Tarjetas por API (el banco solo opera sobre sus tarjetas) ----------
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
  ch:=plone27_card_authorize(c.id,p_importe,m,null);
  update plone27_card_charges set idem_key=p_key where id=ch;
  select cg.status into st from plone27_card_charges cg where cg.id=ch;
  return jsonb_build_object('cargo',ch,'estado',st);
end $$;

create or replace function plone27_bk_card_settle(p_bank uuid,p_charge uuid,p_key text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ok boolean; tx uuid; st text; begin
  select exists(select 1 from plone27_card_charges cg join plone27_cards cd on cd.id=cg.card_id
                join plone27_accounts a on a.id=cd.account_id where cg.id=p_charge and a.bank_id=p_bank) into ok;
  if not ok then raise exception 'Cargo no encontrado'; end if;
  tx:=plone27_card_settle(p_key,p_charge,null);
  select cg.status into st from plone27_card_charges cg where cg.id=p_charge;
  return jsonb_build_object('transaccion',tx,'estado',st);
end $$;

create or replace function plone27_bk_card_release(p_bank uuid,p_charge uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cg plone27_card_charges; begin
  select cg.* into cg from plone27_card_charges cg join plone27_cards cd on cd.id=cg.card_id
    join plone27_accounts a on a.id=cd.account_id
    where cg.id=p_charge and a.bank_id=p_bank for update of cg;
  if cg.id is null then raise exception 'Cargo no encontrado'; end if;
  if cg.status<>'authorized' then raise exception 'Solo se liberan cargos autorizados'; end if;
  if cg.reservation_id is not null then perform plone27_release(cg.reservation_id,null); end if;
  update plone27_card_charges set status='released' where id=p_charge;
  return jsonb_build_object('estado','released');
end $$;

-- ---------- Lectura de nóminas y planes por entidad ----------
create or replace function plone27_bk_nominas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.proximo_pago),'[]'::jsonb) from (
    select c.id, c.gross_monthly as bruto, c.pay_day as dia_pago, c.next_pay as proximo_pago, c.status as estado,
           c.full_time as jornada_completa, c.start_date as inicio
    from plone27_contracts c where c.bank_id=p_bank) x $$;

create or replace function plone27_bk_planes(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.proximo),'[]'::jsonb) from (
    select p.id, p.kind as tipo, p.principal, p.installments as cuotas, p.status as estado, p.next_due as proximo,
           (select count(*) from plone27_plan_items i where i.plan_id=p.id and i.status='pending') as cuotas_pendientes
    from plone27_plans p where p.bank_id=p_bank) x $$;

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

-- ==================== MIGRACIÓN (0024_plone27_disenos_comprados.sql) ====================
-- Placeta One · 0024 · Diseños comprados por el usuario: listado y aplicación a sus tarjetas.
-- Requiere 0023. Idempotente.

-- Diseños comprados por el usuario en su entidad, con la cuenta que los compró y la fecha de la compra
create or replace function plone27_user_disenos_comprados(p_user uuid,p_bank uuid)
returns table(codigo text,nombre text,nivel text,rareza text,imagen_url text,animacion_url text,
              comprado timestamptz,cuenta_iban text,transaccion uuid,tarjetas_con_diseno int)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
    select d.codigo, d.name, d.tier, d.rareza, d.imagen_url, d.animacion_url,
           t.created_at, a.iban, p.tx,
           (select count(*)::int from plone27_cards cd where cd.design_id=d.id and cd.account_id=p.account_id)
    from plone27_design_purchases p
      join plone27_account_members m on m.account_id=p.account_id and m.user_id=p_user
      join plone27_accounts a on a.id=p.account_id and a.bank_id=p_bank
      join plone27_card_designs d on d.id=p.design_id
      left join plone27_transactions t on t.id=p.tx
    order by t.created_at desc nulls last, d.name;
end $$;

-- Aplica un diseño comprado por la cuenta de la tarjeta (o lo quita con p_codigo nulo)
create or replace function plone27_user_card_design(p_user uuid,p_bank uuid,p_ref text,p_codigo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; did uuid; begin
  select cd.* into c from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
    where cd.card_ref=p_ref and a.bank_id=p_bank;
  if c.id is null or not plone27_user_can(p_user,c.account_id,true,p_bank) then raise exception 'Tarjeta no encontrada'; end if;
  if c.status not in('active','suspended') then raise exception 'Esta tarjeta no admite cambios de diseño'; end if;
  if p_codigo is null then
    update plone27_cards set design_id=null where id=c.id;
  else
    select d.id into did from plone27_card_designs d where d.codigo=p_codigo;
    if did is null or not exists(select 1 from plone27_design_purchases p where p.design_id=did and p.account_id=c.account_id) then
      raise exception 'No has comprado este diseño para la cuenta de esta tarjeta';
    end if;
    update plone27_cards set design_id=did where id=c.id;
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'card_design','card',c.id::text,jsonb_build_object('persona',p_user,'diseno',p_codigo));
  return jsonb_build_object('diseno',p_codigo);
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

-- ==================== MIGRACIÓN (0025_plone27_diseno_publicado_con_imagen.sql) ====================
-- Placeta One · 0025 · Un diseño no puede publicarse en la API sin imagen.
-- Requiere 0024. Idempotente (el generador de instalación la hace reejecutable).
do $$ begin alter table plone27_card_designs add constraint plone27_design_publicado_imagen_ck
  check(not publicado_api or imagen_url is not null) not valid; exception when duplicate_object then null; end $$;

-- ==================== MIGRACIÓN (0026_plone27_cuenta_institucional.sql) ====================
-- Placeta One · 0026 · Cuenta institucional (fase 1): CIP, organigrama, puestos, multicargos,
-- historial de nombramientos y delegaciones. Requiere 0025. Idempotente.
-- Supuestos: el CIP lo genera la plataforma (CIP-00000001…); las personas se identifican por DIP.

create sequence if not exists plone27_cip_seq;

create table if not exists plone27_entidades(
  account_id uuid primary key references plone27_accounts,
  bank_id uuid not null references plone27_banks,
  cip text not null unique default ('CIP-'||lpad(nextval('plone27_cip_seq')::text,8,'0'))
    check(cip ~ '^CIP-[0-9]{8}$'),
  nombre text not null check(length(nombre) between 2 and 120),
  activa boolean not null default true,
  creada timestamptz not null default now());

create table if not exists plone27_unidades(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  padre uuid references plone27_unidades(id),
  tipo text not null check(tipo in('junta','administracion','departamento','subdepartamento','proyecto','institucion','unidad_control')),
  nombre text not null check(length(nombre) between 2 and 120),
  codigo text check(codigo is null or codigo ~ '^[A-Z0-9-]{2,20}$'),
  activa boolean not null default true,
  creada timestamptz not null default now(),
  unique(entidad,codigo));

-- Jerarquía permitida: Junta / Administración → departamentos; departamento → subdepartamentos y proyectos;
-- Junta / Administración → instituciones; departamento, subdepartamento o proyecto → unidades de control.
create or replace function plone27_unidad_jerarquia() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare pt text; pe uuid; begin
  if new.padre is null then
    if new.tipo in('junta','administracion','institucion') then return new; end if;
    raise exception 'Una unidad de tipo % necesita una unidad padre', new.tipo;
  end if;
  if new.padre=new.id then raise exception 'Una unidad no puede depender de sí misma'; end if;
  select u.tipo,u.entidad into pt,pe from plone27_unidades u where u.id=new.padre;
  if pt is null then raise exception 'La unidad padre no existe'; end if;
  if pe<>new.entidad then raise exception 'La unidad padre pertenece a otra entidad'; end if;
  if new.tipo in('junta','administracion') then raise exception 'Junta y Administración no dependen de otra unidad'; end if;
  if new.tipo='departamento' and pt not in('junta','administracion') then raise exception 'Un departamento depende de Junta o Administración'; end if;
  if new.tipo='subdepartamento' and pt<>'departamento' then raise exception 'Un subdepartamento depende de un departamento'; end if;
  if new.tipo='proyecto' and pt not in('departamento','subdepartamento') then raise exception 'Un proyecto depende de un departamento o subdepartamento'; end if;
  if new.tipo='institucion' and pt not in('junta','administracion') then raise exception 'Una institución depende de Junta o Administración'; end if;
  if new.tipo='unidad_control' and pt not in('departamento','subdepartamento','proyecto') then raise exception 'Una unidad de control depende de un departamento, subdepartamento o proyecto'; end if;
  return new; end $$;

drop trigger if exists t_unidad_jerarquia on plone27_unidades;
drop trigger if exists t_unidad_jerarquia on plone27_unidades;
create trigger t_unidad_jerarquia before insert or update on plone27_unidades
  for each row execute function plone27_unidad_jerarquia();

create table if not exists plone27_puestos(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  nombre text not null check(length(nombre) between 2 and 120),
  titulares_max int not null default 1 check(titulares_max between 1 and 50),
  activo boolean not null default true,
  creado timestamptz not null default now());

-- Historial: cada nombramiento queda registrado; el cese cierra el periodo (hasta), no lo borra.
create table if not exists plone27_nombramientos(
  id uuid primary key default gen_random_uuid(),
  puesto uuid not null references plone27_puestos(id),
  persona uuid not null references plone27_personas,
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  nombrado_por uuid,
  cesado_por uuid,
  check(hasta is null or hasta>=desde));
create unique index if not exists plone27_nombramiento_activo_ux on plone27_nombramientos(puesto,persona) where hasta is null;

-- Delegaciones: registro de quién puede actuar en un área. Aún no condicionan las aprobaciones (fase 3).
create table if not exists plone27_delegaciones(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  persona uuid not null references plone27_personas,
  permiso text not null check(permiso in('consultar','proponer','aprobar','ejecutar')),
  limite numeric(18,2) check(limite is null or limite>0),
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  otorgada_por uuid,
  revocada_at timestamptz,
  check(hasta is null or hasta>=desde));

create or replace function plone27_entidad_alta(p_bank uuid,p_account uuid,p_nombre text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c text; begin
  if not exists(select 1 from plone27_accounts a where a.id=p_account and a.bank_id=p_bank) then
    raise exception 'Cuenta no encontrada en la entidad';
  end if;
  insert into plone27_entidades(account_id,bank_id,nombre) values(p_account,p_bank,p_nombre) returning plone27_entidades.cip into c;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'entidad_alta','account',p_account::text,jsonb_build_object('cip',c,'nombre',p_nombre));
  return c; end $$;

create or replace function plone27_unidad_alta(p_entidad uuid,p_tipo text,p_padre uuid,p_nombre text,p_codigo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare uid uuid; begin
  insert into plone27_unidades(entidad,tipo,padre,nombre,codigo) values(p_entidad,p_tipo,p_padre,p_nombre,p_codigo)
    returning plone27_unidades.id into uid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'unidad_alta','unidad',uid::text,jsonb_build_object('tipo',p_tipo,'nombre',p_nombre));
  return uid; end $$;

create or replace function plone27_puesto_alta(p_unidad uuid,p_nombre text,p_titulares int,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; begin
  insert into plone27_puestos(unidad,nombre,titulares_max) values(p_unidad,p_nombre,coalesce(p_titulares,1))
    returning plone27_puestos.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'puesto_alta','puesto',pid::text,jsonb_build_object('nombre',p_nombre));
  return pid; end $$;

-- Nombrar a una persona en un puesto. Una persona puede tener varios puestos (multicargo).
create or replace function plone27_nombrar(p_puesto uuid,p_persona uuid,p_motivo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare maximo int; ocupados int; nid uuid; begin
  select p.titulares_max into maximo from plone27_puestos p where p.id=p_puesto and p.activo;
  if maximo is null then raise exception 'Puesto no encontrado o inactivo'; end if;
  select count(*) into ocupados from plone27_nombramientos n where n.puesto=p_puesto and n.hasta is null;
  if ocupados>=maximo then raise exception 'El puesto está completo (% de %)', ocupados, maximo; end if;
  insert into plone27_nombramientos(puesto,persona,motivo,nombrado_por) values(p_puesto,p_persona,p_motivo,p_actor)
    returning plone27_nombramientos.id into nid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'nombramiento_alta','puesto',p_puesto::text,jsonb_build_object('persona',p_persona,'nombramiento',nid));
  return nid; end $$;

-- Cesar: cierra el periodo activo del nombramiento
create or replace function plone27_cesar(p_nombramiento uuid,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_nombramientos set hasta=current_date,cesado_por=p_actor
            where id=p_nombramiento and hasta is null returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Nombramiento no encontrado o ya cesado'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'nombramiento_cese','nombramiento',p_nombramiento::text,jsonb_build_object('motivo',p_motivo));
end $$;

create or replace function plone27_delegar(p_unidad uuid,p_persona uuid,p_permiso text,p_limite numeric,p_hasta date,p_motivo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare did uuid; begin
  insert into plone27_delegaciones(unidad,persona,permiso,limite,hasta,motivo,otorgada_por)
    values(p_unidad,p_persona,p_permiso,p_limite,p_hasta,p_motivo,p_actor) returning plone27_delegaciones.id into did;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'delegacion_alta','unidad',p_unidad::text,jsonb_build_object('persona',p_persona,'permiso',p_permiso));
  return did; end $$;

create or replace function plone27_revocar_delegacion(p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_delegaciones set revocada_at=now()
            where id=p_id and revocada_at is null returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Delegación no encontrada o ya revocada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'delegacion_revocada','delegacion',p_id::text,'{}'::jsonb);
end $$;

-- Plantilla vigente de una entidad: personas con su puesto y unidad
create or replace function plone27_plantilla(p_entidad uuid)
returns table(persona uuid,unidad text,puesto text,desde date)
language sql stable security definer set search_path=public as $$
  select n.persona, u.nombre, p.nombre, n.desde
  from plone27_nombramientos n
    join plone27_puestos p on p.id=n.puesto
    join plone27_unidades u on u.id=p.unidad
  where u.entidad=p_entidad and n.hasta is null
  order by u.nombre, p.nombre $$;

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

-- ==================== MIGRACIÓN (0027_plone27_institucional_presupuestos_nominas.sql) ====================
-- Placeta One · 0027 · Cuenta institucional (fases 2, 3, 4 y 6): presupuestos jerárquicos, permisos por puesto,
-- delegaciones aplicadas, gastos con doble firma, retribuciones, tareas con complementos, nóminas por periodo,
-- reasignaciones, informes, cierre de unidades y funciones para la API. Requiere 0026. Idempotente.

alter table plone27_entidades add column if not exists presupuesto_anual numeric(18,2) not null default 0 check(presupuesto_anual>=0);
alter table plone27_entidades add column if not exists doble_firma_desde numeric(18,2) check(doble_firma_desde is null or doble_firma_desde>0);

-- ---------- Permisos configurables por puesto ----------
create table if not exists plone27_puesto_permisos(
  puesto uuid not null references plone27_puestos(id),
  accion text not null check(accion in('proponer','aprobar','ejecutar','presupuestar','reasignar','retribuir','organigrama','cerrar')),
  limite numeric(18,2) check(limite is null or limite>0),
  primary key(puesto,accion));

-- ---------- Presupuesto anual por unidad y ejercicio ----------
create table if not exists plone27_presupuestos(
  unidad uuid not null references plone27_unidades(id),
  ejercicio int not null check(ejercicio between 2000 and 2100),
  anual numeric(18,2) not null default 0 check(anual>=0),
  primary key(unidad,ejercicio));

-- ---------- Gastos: propuesto → aprobado → pagado (o rechazado) ----------
create table if not exists plone27_gastos(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  unidad uuid not null references plone27_unidades(id),
  ejercicio int not null check(ejercicio between 2000 and 2100),
  importe numeric(18,2) not null check(importe>0),
  concepto text not null check(length(concepto) between 3 and 200),
  origen text not null default 'manual' check(origen in('manual','tarea','retribucion')),
  beneficiario uuid references plone27_accounts,
  propuesto_por uuid not null references plone27_personas,
  aprobado_por uuid references plone27_personas,
  pagado_por uuid references plone27_personas,
  estado text not null default 'propuesto' check(estado in('propuesto','aprobado','pagado','rechazado')),
  tx uuid,
  idem_key text unique,
  creado timestamptz not null default now(),
  resuelto timestamptz,
  check(aprobado_por is null or aprobado_por<>propuesto_por),
  check(pagado_por is null or pagado_por<>propuesto_por),
  check(pagado_por is null or aprobado_por is null or pagado_por<>aprobado_por));

-- Firmas de doble autorización (importes por encima del umbral de la entidad)
create table if not exists plone27_gasto_firmas(
  gasto uuid not null references plone27_gastos(id),
  persona uuid not null references plone27_personas,
  creada timestamptz not null default now(),
  primary key(gasto,persona));

-- ---------- Retribuciones fijas y complementos autorizados ----------
create table if not exists plone27_retribuciones(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  persona uuid not null references plone27_personas,
  concepto text not null check(length(concepto) between 3 and 120),
  importe numeric(18,2) not null check(importe>0),
  desde date not null,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  autorizada_por uuid not null references plone27_personas,
  creada timestamptz not null default now(),
  check(hasta is null or hasta>=desde));

-- ---------- Tareas que generan un complemento (las registra NEXE u otra app) ----------
create table if not exists plone27_tareas(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  persona uuid not null references plone27_personas,
  unidad uuid not null references plone27_unidades(id),
  concepto text not null check(length(concepto) between 3 and 200),
  importe numeric(18,2) not null check(importe>0),
  referencia_externa text not null unique check(length(referencia_externa) between 1 and 120),
  origen_app text not null check(length(origen_app) between 1 and 60),
  gasto uuid references plone27_gastos(id),
  estado text not null default 'registrada' check(estado in('registrada','validada','pagada','rechazada')),
  creada timestamptz not null default now());

-- ---------- Nóminas pagadas por periodo (idempotencia de la nómina) ----------
create table if not exists plone27_nominas_pagadas(
  persona uuid not null references plone27_personas,
  periodo text not null check(periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  referencia text not null,
  importe numeric(18,2) not null,
  gasto uuid references plone27_gastos(id),
  tx uuid,
  creada timestamptz not null default now(),
  primary key(persona,periodo,referencia));

-- ================= Funciones auxiliares =================
create or replace function plone27_ancestros(p_unidad uuid) returns table(id uuid)
language sql stable security definer set search_path=public as $$
  with recursive a as (
    select u.id, u.padre from plone27_unidades u where u.id=p_unidad
    union all
    select u.id, u.padre from plone27_unidades u join a on u.id=a.padre)
  select a.id from a $$;

create or replace function plone27_descendientes(p_unidad uuid) returns table(id uuid)
language sql stable security definer set search_path=public as $$
  with recursive d as (
    select u.id from plone27_unidades u where u.id=p_unidad
    union all
    select u.id from plone27_unidades u join d on u.padre=d.id)
  select d.id from d $$;

-- Lo comprometido y ejecutado de una unidad y de todas las unidades que dependen de ella
create or replace function plone27_gastado(p_unidad uuid,p_ejercicio int) returns numeric
language sql stable security definer set search_path=public as $$
  select coalesce(sum(g.importe),0) from plone27_gastos g
  where g.ejercicio=p_ejercicio and g.estado in('aprobado','pagado')
    and g.unidad in (select d.id from plone27_descendientes(p_unidad) d) $$;

create or replace function plone27_entidad_de(p_bank uuid,p_cip text) returns uuid
language sql stable security definer set search_path=public as $$
  select e.account_id from plone27_entidades e where e.cip=p_cip and e.bank_id=p_bank and e.activa $$;

create or replace function plone27_tiene_en_entidad(p_persona uuid,p_entidad uuid,p_accion text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_nombramientos n
    join plone27_puestos pu on pu.id=n.puesto and pu.activo
    join plone27_unidades u on u.id=pu.unidad and u.entidad=p_entidad
    join plone27_puesto_permisos pp on pp.puesto=pu.id and pp.accion=p_accion
    where n.persona=p_persona and n.hasta is null) $$;

create or replace function plone27_cuenta_titular(p_persona uuid,p_bank uuid) returns uuid
language sql stable security definer set search_path=public as $$
  select a.id from plone27_account_members m join plone27_accounts a on a.id=m.account_id
  where m.user_id=p_persona and a.bank_id=p_bank and a.kind='personal' and a.status='active' and m.role='holder'
  order by a.iban limit 1 $$;

create or replace function plone27_puesto_de(p_persona uuid,p_entidad uuid) returns uuid
language sql stable security definer set search_path=public as $$
  select u.id from plone27_nombramientos n
    join plone27_puestos pu on pu.id=n.puesto
    join plone27_unidades u on u.id=pu.unidad
  where n.persona=p_persona and n.hasta is null and u.entidad=p_entidad
  order by n.desde limit 1 $$;

-- ¿Puede la persona realizar la acción sobre la unidad? Por puesto (en la unidad o en sus superiores) o por delegación vigente.
create or replace function plone27_puede(p_persona uuid,p_unidad uuid,p_accion text,p_importe numeric) returns boolean
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if exists(select 1 from plone27_nombramientos n
      join plone27_puestos pu on pu.id=n.puesto and pu.activo
      join plone27_puesto_permisos pp on pp.puesto=pu.id and pp.accion=p_accion
    where n.persona=p_persona and n.hasta is null
      and pu.unidad in (select a.id from plone27_ancestros(p_unidad) a)
      and (pp.limite is null or (p_importe is not null and pp.limite>=p_importe))) then
    return true;
  end if;
  if exists(select 1 from plone27_delegaciones d
    where d.persona=p_persona and d.permiso=p_accion and d.revocada_at is null
      and d.desde<=current_date and (d.hasta is null or d.hasta>=current_date)
      and d.unidad in (select a.id from plone27_ancestros(p_unidad) a)
      and (d.limite is null or (p_importe is not null and d.limite>=p_importe))) then
    return true;
  end if;
  return false;
end $$;

-- Presupuesto suficiente en la unidad y en todas sus superiores. Cada nivel debe tener presupuesto.
create or replace function plone27_verificar_presupuesto(p_unidad uuid,p_ejercicio int,p_importe numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; asig numeric; nom text; gast numeric; begin
  for r in select x.id from plone27_ancestros(p_unidad) x loop
    select p.anual into asig from plone27_presupuestos p where p.unidad=r.id and p.ejercicio=p_ejercicio;
    select u.nombre into nom from plone27_unidades u where u.id=r.id;
    if asig is null then raise exception 'La unidad % no tiene presupuesto para %', nom, p_ejercicio; end if;
    gast:=plone27_gastado(r.id,p_ejercicio);
    if gast+p_importe>asig then raise exception 'Presupuesto insuficiente en % (disponible: %)', nom, asig-gast; end if;
  end loop;
end $$;

-- ================= Presupuestos =================
create or replace function plone27_entidad_presupuesto_fijar(p_bank uuid,p_cip text,p_actor uuid,p_importe numeric) returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para presupuestar la entidad'; end if;
  if p_importe is null or p_importe<0 then raise exception 'Importe no válido'; end if;
  update plone27_entidades set presupuesto_anual=p_importe where account_id=ent;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'entidad_presupuesto','account',ent::text,jsonb_build_object('importe',p_importe));
  return p_importe;
end $$;

-- Fija el presupuesto anual de una unidad. Los hijos no pueden sumar más que su unidad, las unidades superiores
-- no pueden sumar más que la entidad, y no se puede bajar de lo ya comprometido.
create or replace function plone27_presupuesto_fijar(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_ejercicio int,p_importe numeric) returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; pad uuid; gast numeric; hijos numeric; hermanas numeric; techo numeric; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if p_importe is null or p_importe<0 then raise exception 'Importe no válido'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_importe) then raise exception 'Sin permiso para presupuestar esta unidad'; end if;
  gast:=plone27_gastado(p_unidad,p_ejercicio);
  if p_importe<gast then raise exception 'El presupuesto no puede quedar por debajo de lo ya comprometido o gastado (%)', gast; end if;
  select coalesce(sum(p.anual),0) into hijos from plone27_presupuestos p join plone27_unidades u on u.id=p.unidad
    where u.padre=p_unidad and p.ejercicio=p_ejercicio;
  if p_importe<hijos then raise exception 'Las unidades inferiores suman % y superan este presupuesto', hijos; end if;
  select u.padre into pad from plone27_unidades u where u.id=p_unidad;
  if pad is not null then
    select coalesce(sum(p.anual),0) into hermanas from plone27_presupuestos p join plone27_unidades u on u.id=p.unidad
      where u.padre=pad and p.ejercicio=p_ejercicio and u.id<>p_unidad;
    select coalesce((select p.anual from plone27_presupuestos p where p.unidad=pad and p.ejercicio=p_ejercicio),0) into techo;
    if hermanas+p_importe>techo then raise exception 'Las unidades de este nivel superan el presupuesto de su unidad superior (%)', techo; end if;
  else
    select coalesce(sum(p.anual),0) into hermanas from plone27_presupuestos p join plone27_unidades u on u.id=p.unidad
      where u.entidad=ent and u.padre is null and p.ejercicio=p_ejercicio and u.id<>p_unidad;
    select e.presupuesto_anual into techo from plone27_entidades e where e.account_id=ent;
    if hermanas+p_importe>techo then raise exception 'Las unidades de primer nivel superan el presupuesto general de la entidad (%)', techo; end if;
  end if;
  insert into plone27_presupuestos(unidad,ejercicio,anual) values(p_unidad,p_ejercicio,p_importe)
    on conflict(unidad,ejercicio) do update set anual=excluded.anual;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'presupuesto_fijar','unidad',p_unidad::text,jsonb_build_object('ejercicio',p_ejercicio,'importe',p_importe));
  return p_importe;
end $$;

-- Mueve presupuesto entre dos unidades con la misma unidad superior. No cambia el total de la entidad.
create or replace function plone27_presupuesto_reasignar(p_bank uuid,p_cip text,p_actor uuid,p_desde uuid,p_hasta uuid,p_ejercicio int,p_importe numeric,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; pd uuid; ph uuid; asig numeric; gast numeric; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_desde=p_hasta then raise exception 'Origen y destino no pueden ser la misma unidad'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_desde and u.entidad=ent) or
     not exists(select 1 from plone27_unidades u where u.id=p_hasta and u.entidad=ent) then
    raise exception 'Unidad no encontrada en la entidad';
  end if;
  select u.padre into pd from plone27_unidades u where u.id=p_desde;
  select u.padre into ph from plone27_unidades u where u.id=p_hasta;
  if pd is distinct from ph then raise exception 'Solo se reasigna entre unidades con la misma unidad superior'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'Importe no válido'; end if;
  if length(coalesce(p_motivo,''))<5 then raise exception 'El motivo es obligatorio (mínimo 5 caracteres)'; end if;
  if not plone27_puede(p_actor,p_desde,'reasignar',p_importe) then raise exception 'Sin permiso para reasignar desde esta unidad'; end if;
  select p.anual into asig from plone27_presupuestos p where p.unidad=p_desde and p.ejercicio=p_ejercicio;
  if asig is null then raise exception 'La unidad de origen no tiene presupuesto para ese ejercicio'; end if;
  gast:=plone27_gastado(p_desde,p_ejercicio);
  if asig-gast<p_importe then raise exception 'Disponible insuficiente en la unidad de origen (%)', asig-gast; end if;
  update plone27_presupuestos set anual=anual-p_importe where unidad=p_desde and ejercicio=p_ejercicio;
  insert into plone27_presupuestos(unidad,ejercicio,anual) values(p_hasta,p_ejercicio,p_importe)
    on conflict(unidad,ejercicio) do update set anual=plone27_presupuestos.anual+excluded.anual;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'presupuesto_reasignar','unidad',p_desde::text,jsonb_build_object('destino',p_hasta,'importe',p_importe,'motivo',p_motivo));
end $$;

-- Informe de una unidad: presupuesto, comprometido, pagado, pendiente y disponible; y sus unidades inferiores
create or replace function plone27_informe_unidad(p_bank uuid,p_cip text,p_unidad uuid,p_ejercicio int) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; asig numeric; gast numeric; pag numeric; pend numeric; hijos jsonb; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  select p.anual into asig from plone27_presupuestos p where p.unidad=p_unidad and p.ejercicio=p_ejercicio;
  gast:=plone27_gastado(p_unidad,p_ejercicio);
  select coalesce(sum(g.importe),0) into pag from plone27_gastos g
    where g.ejercicio=p_ejercicio and g.estado='pagado' and g.unidad in (select d.id from plone27_descendientes(p_unidad) d);
  select coalesce(sum(g.importe),0) into pend from plone27_gastos g
    where g.ejercicio=p_ejercicio and g.estado='propuesto' and g.unidad in (select d.id from plone27_descendientes(p_unidad) d);
  select coalesce(jsonb_agg(jsonb_build_object('unidad',u.id,'nombre',u.nombre,'tipo',u.tipo,
           'anual',coalesce(p.anual,0),'gastado',plone27_gastado(u.id,p_ejercicio)) order by u.nombre),'[]'::jsonb)
    into hijos from plone27_unidades u left join plone27_presupuestos p on p.unidad=u.id and p.ejercicio=p_ejercicio
    where u.padre=p_unidad;
  return jsonb_build_object('unidad',p_unidad,'ejercicio',p_ejercicio,'anual',coalesce(asig,0),'gastado',gast,
    'pagado',pag,'pendiente_aprobacion',pend,'disponible',coalesce(asig,0)-gast,'unidades_inferiores',hijos);
end $$;

-- ================= Gastos =================
create or replace function plone27_gasto_proponer(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_ejercicio int,p_importe numeric,p_concepto text,p_iban text,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ben uuid; gid uuid; begin
  if p_key is not null then
    select g.id into gid from plone27_gastos g where g.idem_key=p_key;
    if gid is not null then return gid; end if;
  end if;
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if exists(select 1 from plone27_ancestros(p_unidad) a join plone27_unidades u on u.id=a.id where not u.activa) then
    raise exception 'La unidad o una de sus superiores está cerrada';
  end if;
  if p_importe is null or p_importe<=0 then raise exception 'Importe no válido'; end if;
  if coalesce(length(p_concepto),0)<3 then raise exception 'Concepto de al menos 3 caracteres'; end if;
  if not plone27_puede(p_actor,p_unidad,'proponer',p_importe) then raise exception 'Sin permiso para proponer gastos en esta unidad'; end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into ben from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank and a.status='active';
    if ben is null then raise exception 'Cuenta beneficiaria no válida'; end if;
  end if;
  insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,beneficiario,propuesto_por,idem_key)
    values(ent,p_unidad,p_ejercicio,p_importe,p_concepto,ben,p_actor,p_key) returning plone27_gastos.id into gid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_propuesto','gasto',gid::text,jsonb_build_object('importe',p_importe,'unidad',p_unidad));
  return gid;
end $$;

-- Aprueba un gasto. Si el importe supera el umbral de doble firma, hacen falta dos personas distintas.
create or replace function plone27_gasto_aprobar(p_bank uuid,p_gasto uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; umbral numeric; n int; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado<>'propuesto' then raise exception 'Solo se aprueban gastos propuestos'; end if;
  if p_actor=g.propuesto_por then raise exception 'Nadie puede aprobar su propio gasto'; end if;
  if not plone27_puede(p_actor,g.unidad,'aprobar',g.importe) then raise exception 'Sin permiso para aprobar este gasto'; end if;
  select e.doble_firma_desde into umbral from plone27_entidades e where e.account_id=g.entidad;
  if umbral is not null and g.importe>umbral then
    insert into plone27_gasto_firmas(gasto,persona) values(p_gasto,p_actor) on conflict do nothing;
    select count(*) into n from plone27_gasto_firmas f where f.gasto=p_gasto;
    if n<2 then return 'pendiente_segunda_firma'; end if;
  end if;
  perform 1 from plone27_presupuestos p where p.ejercicio=g.ejercicio and p.unidad in (select a.id from plone27_ancestros(g.unidad) a) for update;
  perform plone27_verificar_presupuesto(g.unidad,g.ejercicio,g.importe);
  update plone27_gastos set estado='aprobado', aprobado_por=p_actor, resuelto=now() where id=p_gasto;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_aprobado','gasto',p_gasto::text,jsonb_build_object('importe',g.importe));
  return 'aprobado';
end $$;

create or replace function plone27_gasto_rechazar(p_bank uuid,p_gasto uuid,p_actor uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado not in('propuesto','aprobado') then raise exception 'Este gasto ya no se puede rechazar'; end if;
  if p_actor=g.propuesto_por then raise exception 'Nadie puede rechazar su propio gasto'; end if;
  if not plone27_puede(p_actor,g.unidad,'aprobar',g.importe) then raise exception 'Sin permiso para rechazar este gasto'; end if;
  update plone27_gastos set estado='rechazado', resuelto=now() where id=p_gasto;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_rechazado','gasto',p_gasto::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- Ejecuta el pago de un gasto aprobado desde la cuenta de la entidad. Quien propone o aprueba no puede pagar.
create or replace function plone27_gasto_pagar(p_bank uuid,p_gasto uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; tx uuid; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado<>'aprobado' then raise exception 'Solo se pagan gastos aprobados'; end if;
  if p_actor=g.propuesto_por or p_actor=g.aprobado_por then raise exception 'Quien propone o aprueba no puede ejecutar el pago'; end if;
  if exists(select 1 from plone27_gasto_firmas f where f.gasto=p_gasto and f.persona=p_actor) then raise exception 'Quien firma no puede ejecutar el pago'; end if;
  if g.beneficiario is null then raise exception 'El gasto no tiene cuenta beneficiaria'; end if;
  if not plone27_puede(p_actor,g.unidad,'ejecutar',g.importe) then raise exception 'Sin permiso para ejecutar este pago'; end if;
  tx:=plone27_transfer('gasto:'||g.id::text,g.entidad,g.beneficiario,g.importe,g.concepto,p_actor);
  update plone27_gastos set estado='pagado', pagado_por=p_actor, tx=tx, resuelto=now() where id=p_gasto;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'gasto_pagado','gasto',p_gasto::text,jsonb_build_object('importe',g.importe,'tx',tx));
  return tx;
end $$;

-- ================= Retribuciones y tareas =================
create or replace function plone27_retribucion_fijar(p_bank uuid,p_cip text,p_actor uuid,p_persona uuid,p_concepto text,p_importe numeric,p_desde date,p_hasta date,p_motivo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; unidad uuid; rid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  unidad:=plone27_puesto_de(p_persona,ent);
  if unidad is null then raise exception 'La persona no tiene puesto en la entidad'; end if;
  if p_actor=p_persona then raise exception 'Nadie puede autorizar su propia retribución'; end if;
  if not plone27_puede(p_actor,unidad,'retribuir',p_importe) then raise exception 'Sin permiso para retribuir a esta persona'; end if;
  insert into plone27_retribuciones(entidad,persona,concepto,importe,desde,hasta,motivo,autorizada_por)
    values(ent,p_persona,p_concepto,p_importe,p_desde,p_hasta,p_motivo,p_actor) returning plone27_retribuciones.id into rid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'retribucion_fijada','retribucion',rid::text,jsonb_build_object('importe',p_importe,'concepto',p_concepto));
  return rid;
end $$;

-- Una tarea registrada por una app externa genera un gasto propuesto a nombre de la persona que la realizó.
create or replace function plone27_tarea_registrar(p_bank uuid,p_cip text,p_persona uuid,p_unidad uuid,p_concepto text,p_importe numeric,p_referencia text,p_origen text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ben uuid; gid uuid; tid uuid; begin
  select t.id into tid from plone27_tareas t where t.referencia_externa=p_referencia;
  if tid is not null then return tid; end if;
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  if plone27_puesto_de(p_persona,ent) is null then raise exception 'La persona no tiene puesto en la entidad'; end if;
  ben:=plone27_cuenta_titular(p_persona,p_bank);
  if ben is null then raise exception 'La persona no tiene cuenta en la entidad'; end if;
  insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,origen,beneficiario,propuesto_por)
    values(ent,p_unidad,extract(year from current_date)::int,p_importe,p_concepto,'tarea',ben,p_persona)
    returning plone27_gastos.id into gid;
  insert into plone27_tareas(entidad,persona,unidad,concepto,importe,referencia_externa,origen_app,gasto)
    values(ent,p_persona,p_unidad,p_concepto,p_importe,p_referencia,p_origen,gid) returning plone27_tareas.id into tid;
  return tid;
end $$;

create or replace function plone27_tarea_validar(p_bank uuid,p_tarea uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t plone27_tareas; r text; begin
  select * into t from plone27_tareas where id=p_tarea for update;
  if t.id is null or not exists(select 1 from plone27_entidades e where e.account_id=t.entidad and e.bank_id=p_bank) then raise exception 'Tarea no encontrada'; end if;
  if t.estado<>'registrada' then raise exception 'La tarea no está pendiente de validación'; end if;
  r:=plone27_gasto_aprobar(p_bank,t.gasto,p_actor);
  if r='aprobado' then update plone27_tareas set estado='validada' where id=p_tarea; end if;
  return r;
end $$;

create or replace function plone27_tarea_pagar(p_bank uuid,p_tarea uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t plone27_tareas; tx uuid; begin
  select * into t from plone27_tareas where id=p_tarea for update;
  if t.id is null or not exists(select 1 from plone27_entidades e where e.account_id=t.entidad and e.bank_id=p_bank) then raise exception 'Tarea no encontrada'; end if;
  if t.estado<>'validada' then raise exception 'Solo se pagan tareas validadas'; end if;
  tx:=plone27_gasto_pagar(p_bank,t.gasto,p_actor);
  update plone27_tareas set estado='pagada' where id=p_tarea;
  return tx;
end $$;

create or replace function plone27_tarea_rechazar(p_bank uuid,p_tarea uuid,p_actor uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t plone27_tareas; begin
  select * into t from plone27_tareas where id=p_tarea for update;
  if t.id is null or not exists(select 1 from plone27_entidades e where e.account_id=t.entidad and e.bank_id=p_bank) then raise exception 'Tarea no encontrada'; end if;
  if t.estado not in('registrada','validada') then raise exception 'Esta tarea ya no se puede rechazar'; end if;
  perform plone27_gasto_rechazar(p_bank,t.gasto,p_actor,p_motivo);
  update plone27_tareas set estado='rechazada' where id=p_tarea;
end $$;

-- ================= Nómina por periodo =================
-- Paga todas las retribuciones fijas vigentes en el periodo (AAAA-MM). Una nómina ya pagada no se repite.
-- Si un solo pago no tiene presupuesto, no se paga ninguno (la transacción se deshace).
create or replace function plone27_nomina_periodo(p_bank uuid,p_cip text,p_actor uuid,p_periodo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ini date; fin date; ejer int; r plone27_retribuciones; unidad uuid; ben uuid; ref text; gid uuid; tx uuid; n int:=0; total numeric:=0; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'ejecutar') then raise exception 'Sin permiso para ejecutar nóminas'; end if;
  ini:=to_date(p_periodo||'-01','YYYY-MM-DD');
  fin:=(ini+interval '1 month'-interval '1 day')::date;
  ejer:=extract(year from ini)::int;
  for r in select x.* from plone27_retribuciones x
           where x.entidad=ent and x.desde<=fin and (x.hasta is null or x.hasta>=ini) order by x.id loop
    ref:='retribucion:'||r.id::text;
    if exists(select 1 from plone27_nominas_pagadas np where np.persona=r.persona and np.periodo=p_periodo and np.referencia=ref) then
      continue;
    end if;
    unidad:=plone27_puesto_de(r.persona,ent);
    if unidad is null then raise exception 'Una persona con retribución no tiene puesto en la entidad'; end if;
    ben:=plone27_cuenta_titular(r.persona,p_bank);
    if ben is null then raise exception 'Una persona con retribución no tiene cuenta en la entidad'; end if;
    if r.autorizada_por=p_actor then raise exception 'Quien autoriza una retribución no puede ejecutar la nómina'; end if;
    perform plone27_verificar_presupuesto(unidad,ejer,r.importe);
    tx:=plone27_transfer('nomina:'||p_periodo||':'||r.id::text,ent,ben,r.importe,'Nómina '||p_periodo,p_actor);
    insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,origen,beneficiario,propuesto_por,pagado_por,estado,tx,resuelto)
      values(ent,unidad,ejer,r.importe,r.concepto||' '||p_periodo,'retribucion',ben,r.autorizada_por,p_actor,'pagado',tx,now())
      returning plone27_gastos.id into gid;
    insert into plone27_nominas_pagadas(persona,periodo,referencia,importe,gasto,tx)
      values(r.persona,p_periodo,ref,r.importe,gid,tx);
    n:=n+1; total:=total+r.importe;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'nomina_periodo','account',ent::text,jsonb_build_object('periodo',p_periodo,'pagos',n,'total',total));
  return jsonb_build_object('periodo',p_periodo,'pagos',n,'total',total);
end $$;

-- ================= Organigrama para la API (con comprobación de permisos y entidad) =================
create or replace function plone27_arbol(p_bank uuid,p_cip text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; resultado jsonb; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then return null; end if;
  select jsonb_build_object('entidad',e.nombre,'cip',e.cip,
    'unidades',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'padre',u.padre,'tipo',u.tipo,'nombre',u.nombre,'codigo',u.codigo,'activa',u.activa) order by u.nombre),'[]'::jsonb)
                from plone27_unidades u where u.entidad=ent),
    'puestos',(select coalesce(jsonb_agg(jsonb_build_object('id',pu.id,'unidad',pu.unidad,'nombre',pu.nombre,'titulares_max',pu.titulares_max,'activo',pu.activo) order by pu.nombre),'[]'::jsonb)
                from plone27_puestos pu join plone27_unidades u on u.id=pu.unidad where u.entidad=ent),
    'nombramientos',(select coalesce(jsonb_agg(jsonb_build_object('dip',pe.dip,'puesto',n.puesto,'desde',n.desde) order by n.desde),'[]'::jsonb)
                from plone27_nombramientos n join plone27_puestos pu on pu.id=n.puesto
                join plone27_unidades u on u.id=pu.unidad join plone27_personas pe on pe.id=n.persona
                where u.entidad=ent and n.hasta is null))
  into resultado from plone27_entidades e where e.account_id=ent;
  return resultado;
end $$;

-- Expediente de una persona en la entidad: puestos, retribuciones vigentes, tareas y nóminas pagadas
create or replace function plone27_expediente(p_bank uuid,p_cip text,p_persona uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then return null; end if;
  return jsonb_build_object(
    'puestos',(select coalesce(jsonb_agg(jsonb_build_object('puesto',pu.nombre,'unidad',u.nombre,'desde',n.desde) order by n.desde),'[]'::jsonb)
               from plone27_nombramientos n join plone27_puestos pu on pu.id=n.puesto join plone27_unidades u on u.id=pu.unidad
               where n.persona=p_persona and n.hasta is null and u.entidad=ent),
    'retribuciones',(select coalesce(jsonb_agg(jsonb_build_object('concepto',r.concepto,'importe',r.importe,'desde',r.desde,'hasta',r.hasta) order by r.desde),'[]'::jsonb)
               from plone27_retribuciones r where r.persona=p_persona and r.entidad=ent and (r.hasta is null or r.hasta>=current_date)),
    'tareas',(select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) from (
               select t.id,t.concepto,t.importe,t.estado,t.referencia_externa as referencia from plone27_tareas t
               where t.persona=p_persona and t.entidad=ent order by t.creada desc limit 50) x),
    'nominas',(select coalesce(jsonb_agg(to_jsonb(y)),'[]'::jsonb) from (
               select np.periodo,np.importe from plone27_nominas_pagadas np join plone27_gastos g on g.id=np.gasto
               where np.persona=p_persona and g.entidad=ent order by np.periodo desc limit 24) y));
end $$;

-- ================= Organigrama con permisos (API de bancos) =================
create or replace function plone27_org_unidad_nueva(p_bank uuid,p_cip text,p_actor uuid,p_tipo text,p_padre uuid,p_nombre text,p_codigo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if p_padre is not null and not exists(select 1 from plone27_unidades u where u.id=p_padre and u.entidad=ent and u.activa) then
    raise exception 'Unidad superior no válida o cerrada';
  end if;
  return plone27_unidad_alta(ent,p_tipo,p_padre,p_nombre,p_codigo,p_actor);
end $$;

create or replace function plone27_org_puesto_nuevo(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_nombre text,p_titulares int) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  return plone27_puesto_alta(p_unidad,p_nombre,p_titulares,p_actor);
end $$;

create or replace function plone27_org_nombrar(p_bank uuid,p_cip text,p_actor uuid,p_puesto uuid,p_persona uuid,p_motivo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_puestos pu join plone27_unidades u on u.id=pu.unidad where pu.id=p_puesto and u.entidad=ent) then
    raise exception 'Puesto no encontrado en la entidad';
  end if;
  return plone27_nombrar(p_puesto,p_persona,p_motivo,p_actor);
end $$;

create or replace function plone27_org_cesar(p_bank uuid,p_cip text,p_actor uuid,p_nombramiento uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_nombramientos n join plone27_puestos pu on pu.id=n.puesto
                join plone27_unidades u on u.id=pu.unidad where n.id=p_nombramiento and u.entidad=ent) then
    raise exception 'Nombramiento no encontrado en la entidad';
  end if;
  perform plone27_cesar(p_nombramiento,p_motivo,p_actor);
end $$;

create or replace function plone27_org_permiso(p_bank uuid,p_cip text,p_actor uuid,p_puesto uuid,p_accion text,p_limite numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if not exists(select 1 from plone27_puestos pu join plone27_unidades u on u.id=pu.unidad where pu.id=p_puesto and u.entidad=ent) then
    raise exception 'Puesto no encontrado en la entidad';
  end if;
  insert into plone27_puesto_permisos(puesto,accion,limite) values(p_puesto,p_accion,p_limite)
    on conflict(puesto,accion) do update set limite=excluded.limite;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'puesto_permiso','puesto',p_puesto::text,jsonb_build_object('accion',p_accion,'limite',p_limite));
end $$;

-- Permisos de puesto para el personal del banco (arranque del sistema). No se expone a las APIs.
create or replace function plone27_puesto_permiso_fijar_staff(p_puesto uuid,p_accion text,p_limite numeric,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  insert into plone27_puesto_permisos(puesto,accion,limite) values(p_puesto,p_accion,p_limite)
    on conflict(puesto,accion) do update set limite=excluded.limite;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'puesto_permiso_staff','puesto',p_puesto::text,jsonb_build_object('accion',p_accion,'limite',p_limite));
end $$;

create or replace function plone27_org_cerrar_unidad(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'cerrar',null) then raise exception 'Sin permiso para cerrar esta unidad'; end if;
  if exists(select 1 from plone27_gastos g where g.estado in('propuesto','aprobado')
            and g.unidad in (select d.id from plone27_descendientes(p_unidad) d)) then
    raise exception 'Hay gastos pendientes o comprometidos en esta unidad';
  end if;
  update plone27_unidades set activa=false where id=p_unidad;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'unidad_cerrada','unidad',p_unidad::text,jsonb_build_object('motivo',p_motivo));
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

-- ==================== MIGRACIÓN (0028_plone27_fondos_recurrentes_solicitudes.sql) ====================
-- Placeta One · 0028 · Cuenta institucional (completar): fondos restringidos, presupuestos mensuales y plurianuales,
-- pagos recurrentes, convocatorias internas, solicitudes de unidades (activables por la entidad) y eventos de webhook
-- para gastos, tareas y nóminas. Requiere 0027. Idempotente.

alter table plone27_entidades add column if not exists solicitudes_activas boolean not null default false;
alter table plone27_gastos add column if not exists fecha date not null default current_date;

-- ---------- Fondos restringidos a una finalidad ----------
create table if not exists plone27_fondos(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  nombre text not null check(length(nombre) between 2 and 120),
  finalidad text not null check(length(finalidad) between 5 and 300),
  importe numeric(18,2) not null check(importe>0),
  activo boolean not null default true,
  creado timestamptz not null default now(),
  unique(unidad,nombre));
alter table plone27_gastos add column if not exists fondo uuid references plone27_fondos(id);

-- ---------- Presupuesto mensual (reparto del anual) y plan plurianual (sobre de varios años) ----------
create table if not exists plone27_presupuesto_meses(
  unidad uuid not null references plone27_unidades(id),
  ejercicio int not null check(ejercicio between 2000 and 2100),
  mes int not null check(mes between 1 and 12),
  importe numeric(18,2) not null check(importe>=0),
  primary key(unidad,ejercicio,mes));

create table if not exists plone27_planes_plurianuales(
  id uuid primary key default gen_random_uuid(),
  unidad uuid not null references plone27_unidades(id),
  nombre text not null check(length(nombre) between 2 and 120),
  ejercicio_inicio int not null check(ejercicio_inicio between 2000 and 2100),
  ejercicio_fin int not null check(ejercicio_fin between 2000 and 2100),
  total numeric(18,2) not null check(total>0),
  creado timestamptz not null default now(),
  check(ejercicio_fin>=ejercicio_inicio and ejercicio_fin-ejercicio_inicio<=9));

-- ---------- Pagos recurrentes autorizados ----------
create table if not exists plone27_recurrentes(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  unidad uuid not null references plone27_unidades(id),
  concepto text not null check(length(concepto) between 3 and 200),
  importe numeric(18,2) not null check(importe>0),
  beneficiario uuid references plone27_accounts,
  periodicidad_meses int not null check(periodicidad_meses between 1 and 12),
  desde date not null,
  hasta date,
  autorizada_por uuid not null references plone27_personas,
  activo boolean not null default true,
  creada timestamptz not null default now(),
  check(hasta is null or hasta>=desde));

create table if not exists plone27_recurrentes_generados(
  recurrente uuid not null references plone27_recurrentes(id),
  periodo text not null check(periodo ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  gasto uuid references plone27_gastos(id),
  primary key(recurrente,periodo));

-- ---------- Convocatorias internas y solicitudes de unidades ----------
create table if not exists plone27_convocatorias(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  nombre text not null check(length(nombre) between 3 and 120),
  importe numeric(18,2) not null check(importe>0),
  desde date not null,
  hasta date not null,
  estado text not null default 'abierta' check(estado in('abierta','cerrada')),
  creada timestamptz not null default now(),
  check(hasta>=desde));

create table if not exists plone27_solicitudes_unidad(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  unidad uuid not null references plone27_unidades(id),
  tipo text not null check(tipo in('ampliacion','prorroga','reserva_extra','financiacion','otra')),
  importe numeric(18,2) check(importe is null or importe>0),
  referencia uuid,
  convocatoria uuid references plone27_convocatorias(id),
  nueva_fecha date,
  justificacion text not null check(length(justificacion) between 20 and 1000),
  estado text not null default 'pendiente' check(estado in('pendiente','concedida','denegada')),
  solicitada_por uuid not null references plone27_personas,
  resuelta_por uuid references plone27_personas,
  resolucion text check(resolucion is null or length(resolucion)<=500),
  creada timestamptz not null default now(),
  resuelta timestamptz,
  check(resuelta_por is null or resuelta_por<>solicitada_por));

-- ================= Reglas automáticas (disparadores) =================

-- Reparto mensual: no puede superar el anual
create or replace function plone27_trg_mes_valido() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare anual numeric; suma numeric; begin
  select p.anual into anual from plone27_presupuestos p where p.unidad=new.unidad and p.ejercicio=new.ejercicio;
  if anual is null then raise exception 'Primero hay que fijar el presupuesto anual de la unidad'; end if;
  select coalesce(sum(m.importe),0) into suma from plone27_presupuesto_meses m
    where m.unidad=new.unidad and m.ejercicio=new.ejercicio and m.mes<>new.mes;
  if suma+new.importe>anual then raise exception 'El reparto mensual supera el presupuesto anual (%)', anual; end if;
  return new;
end $$;
drop trigger if exists trg_mes_valido on plone27_presupuesto_meses;
drop trigger if exists trg_mes_valido on plone27_presupuesto_meses;
create trigger trg_mes_valido before insert or update on plone27_presupuesto_meses
  for each row execute function plone27_trg_mes_valido();

-- Cambiar el anual no puede dejar por debajo el reparto mensual ni el sobre de un plan plurianual
create or replace function plone27_trg_presupuesto_coherente() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare suma_meses numeric; suma_plan numeric; pl record; begin
  select coalesce(sum(m.importe),0) into suma_meses from plone27_presupuesto_meses m
    where m.unidad=new.unidad and m.ejercicio=new.ejercicio;
  if suma_meses>new.anual then raise exception 'El reparto mensual (%) supera el nuevo presupuesto anual', suma_meses; end if;
  for pl in select x.* from plone27_planes_plurianuales x
            where x.unidad=new.unidad and new.ejercicio between x.ejercicio_inicio and x.ejercicio_fin loop
    select coalesce(sum(p.anual),0) into suma_plan from plone27_presupuestos p
      where p.unidad=new.unidad and p.ejercicio between pl.ejercicio_inicio and pl.ejercicio_fin;
    if suma_plan>pl.total then raise exception 'El plan plurianual "%" supera su total (%)', pl.nombre, pl.total; end if;
  end loop;
  return new;
end $$;
drop trigger if exists trg_presupuesto_coherente on plone27_presupuestos;
drop trigger if exists trg_presupuesto_coherente on plone27_presupuestos;
create trigger trg_presupuesto_coherente after insert or update on plone27_presupuestos
  for each row execute function plone27_trg_presupuesto_coherente();

-- Al aprobar un gasto: saldo del fondo y saldo del mes (si hay presupuesto mensual)
create or replace function plone27_trg_gasto_saldos() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare fmax numeric; usado numeric; mes_b numeric; usado_mes numeric; mes int; begin
  if new.estado<>'aprobado' or old.estado='aprobado' then return new; end if;
  if new.fondo is not null then
    select f.importe into fmax from plone27_fondos f where f.id=new.fondo;
    select coalesce(sum(g.importe),0) into usado from plone27_gastos g
      where g.fondo=new.fondo and g.estado in('aprobado','pagado') and g.id<>new.id;
    if usado+new.importe>fmax then raise exception 'El fondo no tiene saldo suficiente (disponible: %)', fmax-usado; end if;
  end if;
  mes:=extract(month from new.fecha)::int;
  select m.importe into mes_b from plone27_presupuesto_meses m
    where m.unidad=new.unidad and m.ejercicio=new.ejercicio and m.mes=mes;
  if mes_b is not null then
    select coalesce(sum(g.importe),0) into usado_mes from plone27_gastos g
      where g.unidad=new.unidad and g.ejercicio=new.ejercicio and extract(month from g.fecha)::int=mes
        and g.estado in('aprobado','pagado') and g.id<>new.id;
    if usado_mes+new.importe>mes_b then raise exception 'Presupuesto del mes insuficiente (disponible: %)', mes_b-usado_mes; end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_gasto_saldos on plone27_gastos;
drop trigger if exists trg_gasto_saldos on plone27_gastos;
create trigger trg_gasto_saldos before update of estado on plone27_gastos
  for each row execute function plone27_trg_gasto_saldos();

-- Eventos de webhook: gastos, tareas y nóminas
create or replace function plone27_trg_evento_gasto() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare bk uuid; begin
  if tg_op='UPDATE' and new.estado=old.estado then return new; end if;
  select e.bank_id into bk from plone27_entidades e where e.account_id=new.entidad;
  insert into plone27_outbox(event,bank_ids,payload) values('gasto.'||new.estado,array[bk],
    jsonb_build_object('gasto',new.id,'unidad',new.unidad,'ejercicio',new.ejercicio,'importe',new.importe,
      'concepto',new.concepto,'origen',new.origen,'estado',new.estado));
  return new;
end $$;
drop trigger if exists trg_evento_gasto on plone27_gastos;
drop trigger if exists trg_evento_gasto on plone27_gastos;
create trigger trg_evento_gasto after insert or update of estado on plone27_gastos
  for each row execute function plone27_trg_evento_gasto();

create or replace function plone27_trg_evento_tarea() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare bk uuid; dni text; begin
  if tg_op='UPDATE' and new.estado=old.estado then return new; end if;
  select e.bank_id into bk from plone27_entidades e where e.account_id=new.entidad;
  select p.dip into dni from plone27_personas p where p.id=new.persona;
  insert into plone27_outbox(event,bank_ids,payload) values('tarea.'||new.estado,array[bk],
    jsonb_build_object('tarea',new.id,'referencia',new.referencia_externa,'dip',dni,'concepto',new.concepto,
      'importe',new.importe,'estado',new.estado));
  return new;
end $$;
drop trigger if exists trg_evento_tarea on plone27_tareas;
drop trigger if exists trg_evento_tarea on plone27_tareas;
create trigger trg_evento_tarea after insert or update of estado on plone27_tareas
  for each row execute function plone27_trg_evento_tarea();

create or replace function plone27_trg_evento_nomina() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare bk uuid; ent uuid; dni text; begin
  select g.entidad into ent from plone27_gastos g where g.id=new.gasto;
  select e.bank_id into bk from plone27_entidades e where e.account_id=ent;
  select p.dip into dni from plone27_personas p where p.id=new.persona;
  insert into plone27_outbox(event,bank_ids,payload) values('nomina.pagada',array[bk],
    jsonb_build_object('dip',dni,'periodo',new.periodo,'importe',new.importe,'referencia',new.referencia,'gasto',new.gasto));
  return new;
end $$;
drop trigger if exists trg_evento_nomina on plone27_nominas_pagadas;
drop trigger if exists trg_evento_nomina on plone27_nominas_pagadas;
create trigger trg_evento_nomina after insert on plone27_nominas_pagadas
  for each row execute function plone27_trg_evento_nomina();

-- ================= Funciones de gestión =================

create or replace function plone27_entidad_config(p_bank uuid,p_cip text,p_actor uuid,p_solicitudes boolean,p_doble_firma numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para configurar la entidad'; end if;
  update plone27_entidades set solicitudes_activas=coalesce(p_solicitudes,false), doble_firma_desde=p_doble_firma where account_id=ent;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'entidad_config','account',ent::text,jsonb_build_object('solicitudes',p_solicitudes,'doble_firma',p_doble_firma));
end $$;

create or replace function plone27_presupuesto_mes_fijar(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_ejercicio int,p_mes int,p_importe numeric) returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_importe) then raise exception 'Sin permiso para presupuestar esta unidad'; end if;
  insert into plone27_presupuesto_meses(unidad,ejercicio,mes,importe) values(p_unidad,p_ejercicio,p_mes,p_importe)
    on conflict(unidad,ejercicio,mes) do update set importe=excluded.importe;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'presupuesto_mes','unidad',p_unidad::text,jsonb_build_object('ejercicio',p_ejercicio,'mes',p_mes,'importe',p_importe));
  return p_importe;
end $$;

create or replace function plone27_plan_plurianual_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_nombre text,p_inicio int,p_fin int,p_total numeric) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ya numeric; pid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_total) then raise exception 'Sin permiso para presupuestar esta unidad'; end if;
  select coalesce(sum(p.anual),0) into ya from plone27_presupuestos p
    where p.unidad=p_unidad and p.ejercicio between p_inicio and p_fin;
  if ya>p_total then raise exception 'Los presupuestos anuales ya suman % en esos años', ya; end if;
  insert into plone27_planes_plurianuales(unidad,nombre,ejercicio_inicio,ejercicio_fin,total)
    values(p_unidad,p_nombre,p_inicio,p_fin,p_total) returning plone27_planes_plurianuales.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'plan_plurianual','unidad',p_unidad::text,jsonb_build_object('plan',pid,'total',p_total));
  return pid;
end $$;

create or replace function plone27_fondo_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_nombre text,p_finalidad text,p_importe numeric) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; fid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent) then raise exception 'Unidad no encontrada en la entidad'; end if;
  if not plone27_puede(p_actor,p_unidad,'presupuestar',p_importe) then raise exception 'Sin permiso para crear fondos en esta unidad'; end if;
  insert into plone27_fondos(unidad,nombre,finalidad,importe) values(p_unidad,p_nombre,p_finalidad,p_importe)
    returning plone27_fondos.id into fid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'fondo_crear','unidad',p_unidad::text,jsonb_build_object('fondo',fid,'importe',p_importe));
  return fid;
end $$;

-- Asigna un fondo a un gasto propuesto. Solo quien propone el gasto, y el fondo debe ser de su unidad o de una superior.
create or replace function plone27_gasto_asignar_fondo(p_bank uuid,p_gasto uuid,p_actor uuid,p_fondo uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_gastos; begin
  select * into g from plone27_gastos where id=p_gasto for update;
  if g.id is null or not exists(select 1 from plone27_entidades e where e.account_id=g.entidad and e.bank_id=p_bank) then
    raise exception 'Gasto no encontrado';
  end if;
  if g.estado<>'propuesto' then raise exception 'Solo se puede asignar fondo a un gasto propuesto'; end if;
  if p_actor<>g.propuesto_por then raise exception 'Solo quien propone el gasto puede asignarle un fondo'; end if;
  if not exists(select 1 from plone27_fondos f where f.id=p_fondo and f.activo and f.unidad in (select a.id from plone27_ancestros(g.unidad) a)) then
    raise exception 'Fondo no disponible para esta unidad';
  end if;
  update plone27_gastos set fondo=p_fondo where id=p_gasto;
end $$;

create or replace function plone27_recurrente_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_concepto text,p_importe numeric,p_iban text,p_meses int,p_desde date,p_hasta date) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ben uuid; rid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  if not plone27_puede(p_actor,p_unidad,'aprobar',p_importe) then raise exception 'Sin permiso para autorizar pagos recurrentes en esta unidad'; end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into ben from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank and a.status='active';
    if ben is null then raise exception 'Cuenta beneficiaria no válida'; end if;
  end if;
  insert into plone27_recurrentes(entidad,unidad,concepto,importe,beneficiario,periodicidad_meses,desde,hasta,autorizada_por)
    values(ent,p_unidad,p_concepto,p_importe,ben,p_meses,p_desde,p_hasta,p_actor) returning plone27_recurrentes.id into rid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'recurrente_crear','unidad',p_unidad::text,jsonb_build_object('recurrente',rid,'importe',p_importe));
  return rid;
end $$;

-- Genera las propuestas de gasto de los pagos recurrentes que tocan en el periodo (AAAA-MM).
-- Cada propuesta sigue su flujo normal: aprobación por otra persona, presupuesto y pago.
create or replace function plone27_recurrentes_generar(p_bank uuid,p_cip text,p_actor uuid,p_periodo text) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ini date; fin date; meses_desde int; meses_periodo int; r plone27_recurrentes; gid uuid; n int:=0; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'aprobar') then raise exception 'Sin permiso para generar pagos recurrentes'; end if;
  ini:=to_date(p_periodo||'-01','YYYY-MM-DD');
  fin:=(ini+interval '1 month'-interval '1 day')::date;
  meses_periodo:=extract(year from ini)::int*12+extract(month from ini)::int;
  for r in select x.* from plone27_recurrentes x
           where x.entidad=ent and x.activo and x.desde<=fin and (x.hasta is null or x.hasta>=ini) order by x.id loop
    meses_desde:=extract(year from r.desde)::int*12+extract(month from r.desde)::int;
    if (meses_periodo-meses_desde)<0 or (meses_periodo-meses_desde)%r.periodicidad_meses<>0 then continue; end if;
    if exists(select 1 from plone27_recurrentes_generados rg where rg.recurrente=r.id and rg.periodo=p_periodo) then continue; end if;
    insert into plone27_gastos(entidad,unidad,ejercicio,importe,concepto,origen,beneficiario,propuesto_por,fecha)
      values(ent,r.unidad,extract(year from ini)::int,r.importe,r.concepto,'manual',r.beneficiario,r.autorizada_por,ini)
      returning plone27_gastos.id into gid;
    insert into plone27_recurrentes_generados(recurrente,periodo,gasto) values(r.id,p_periodo,gid);
    n:=n+1;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'recurrentes_generar','account',ent::text,jsonb_build_object('periodo',p_periodo,'propuestas',n));
  return n;
end $$;

create or replace function plone27_convocatoria_crear(p_bank uuid,p_cip text,p_actor uuid,p_nombre text,p_importe numeric,p_desde date,p_hasta date) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; cid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para abrir convocatorias'; end if;
  insert into plone27_convocatorias(entidad,nombre,importe,desde,hasta) values(ent,p_nombre,p_importe,p_desde,p_hasta)
    returning plone27_convocatorias.id into cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'convocatoria_crear','account',ent::text,jsonb_build_object('convocatoria',cid,'importe',p_importe));
  return cid;
end $$;

-- Solicitud de una unidad. Solo si la entidad tiene activadas las solicitudes.
create or replace function plone27_solicitud_crear(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_tipo text,p_importe numeric,p_referencia uuid,p_nueva_fecha date,p_justificacion text,p_convocatoria uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; activas boolean; sid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  select e.solicitudes_activas into activas from plone27_entidades e where e.account_id=ent;
  if not activas then raise exception 'Las solicitudes no están activadas en esta entidad'; end if;
  if not exists(select 1 from plone27_unidades u where u.id=p_unidad and u.entidad=ent and u.activa) then raise exception 'Unidad no válida o cerrada'; end if;
  if not plone27_puede(p_actor,p_unidad,'proponer',p_importe) then raise exception 'Sin permiso para solicitar en esta unidad'; end if;
  if p_tipo='ampliacion' and coalesce(p_importe,0)<=0 then raise exception 'La ampliación necesita un importe'; end if;
  if p_tipo='reserva_extra' and (p_referencia is null or coalesce(p_importe,0)<=0) then raise exception 'La reserva extra necesita un fondo y un importe'; end if;
  if p_tipo='prorroga' and (p_nueva_fecha is null or p_referencia is null) then raise exception 'La prórroga necesita la fecha nueva y el elemento a prorrogar'; end if;
  if p_tipo='financiacion' and p_convocatoria is null then raise exception 'La financiación necesita una convocatoria'; end if;
  insert into plone27_solicitudes_unidad(entidad,unidad,tipo,importe,referencia,convocatoria,nueva_fecha,justificacion,solicitada_por)
    values(ent,p_unidad,p_tipo,p_importe,p_referencia,p_convocatoria,p_nueva_fecha,p_justificacion,p_actor)
    returning plone27_solicitudes_unidad.id into sid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'solicitud_crear','unidad',p_unidad::text,jsonb_build_object('solicitud',sid,'tipo',p_tipo));
  return sid;
end $$;

-- Resolver una solicitud: quien decide necesita permiso de presupuesto y no puede ser quien la pidió.
create or replace function plone27_solicitud_resolver(p_bank uuid,p_solicitud uuid,p_actor uuid,p_decision text,p_resolucion text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_solicitudes_unidad; cip text; asig numeric; conv plone27_convocatorias; conc numeric; ejer int; begin
  select * into s from plone27_solicitudes_unidad where id=p_solicitud for update;
  if s.id is null or not exists(select 1 from plone27_entidades e where e.account_id=s.entidad and e.bank_id=p_bank) then
    raise exception 'Solicitud no encontrada';
  end if;
  if s.estado<>'pendiente' then raise exception 'La solicitud ya está resuelta'; end if;
  if p_actor=s.solicitada_por then raise exception 'Nadie puede resolver su propia solicitud'; end if;
  if p_decision not in('concedida','denegada') then raise exception 'Decisión no válida'; end if;
  if not plone27_puede(p_actor,s.unidad,'presupuestar',s.importe) then raise exception 'Sin permiso para resolver solicitudes de esta unidad'; end if;
  ejer:=extract(year from current_date)::int;
  if p_decision='concedida' then
    select e.cip into cip from plone27_entidades e where e.account_id=s.entidad;
    if s.tipo='ampliacion' then
      select coalesce((select p.anual from plone27_presupuestos p where p.unidad=s.unidad and p.ejercicio=ejer),0) into asig;
      perform plone27_presupuesto_fijar(p_bank,cip,p_actor,s.unidad,ejer,asig+s.importe);
    elsif s.tipo='reserva_extra' then
      update plone27_fondos set importe=importe+s.importe where id=s.referencia and unidad=s.unidad;
      if not found then raise exception 'El fondo no pertenece a la unidad de la solicitud'; end if;
    elsif s.tipo='prorroga' then
      if exists(select 1 from plone27_convocatorias c where c.id=s.referencia and c.entidad=s.entidad) then
        update plone27_convocatorias set hasta=s.nueva_fecha where id=s.referencia;
      elsif exists(select 1 from plone27_recurrentes r where r.id=s.referencia and r.entidad=s.entidad) then
        update plone27_recurrentes set hasta=s.nueva_fecha where id=s.referencia;
      else
        raise exception 'El elemento a prorrogar no existe en la entidad';
      end if;
    elsif s.tipo='financiacion' then
      select * into conv from plone27_convocatorias where id=s.convocatoria for update;
      if conv.id is null or conv.estado<>'abierta' then raise exception 'La convocatoria no está abierta'; end if;
      select coalesce(sum(x.importe),0) into conc from plone27_solicitudes_unidad x
        where x.convocatoria=conv.id and x.estado='concedida';
      if conc+s.importe>conv.importe then raise exception 'La convocatoria no tiene fondos suficientes (disponible: %)', conv.importe-conc; end if;
      select coalesce((select p.anual from plone27_presupuestos p where p.unidad=s.unidad and p.ejercicio=ejer),0) into asig;
      perform plone27_presupuesto_fijar(p_bank,cip,p_actor,s.unidad,ejer,asig+s.importe);
    end if;
  end if;
  update plone27_solicitudes_unidad set estado=p_decision, resuelta_por=p_actor, resolucion=p_resolucion, resuelta=now() where id=p_solicitud;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'solicitud_resuelta','unidad',s.unidad::text,jsonb_build_object('solicitud',p_solicitud,'decision',p_decision));
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

-- ==================== MIGRACIÓN (0029_plone27_rbu_cuenta_principal.sql) ====================
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

-- ==================== MIGRACIÓN (0030_plone27_tarjeta_prepago_rbu.sql) ====================
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
do $$ begin alter table plone27_card_charges add constraint plone27_card_charges_lote_fk foreign key(lote) references plone27_rbu_lotes(id) not valid; exception when duplicate_object then null; end $$;

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

-- ==================== MIGRACIÓN (0031_plone27_pasarela_tarjetas_comisiones.sql) ====================
-- Placeta One · 0031 · Pasarela con tarjeta y comisiones interbancarias.
-- Tarifa fijada por el propietario por banco; el banco del pagador decide, para cuenta y para tarjeta,
-- si la comisión la paga el cliente o la absorbe. Quién la cobra (propietario o banco del pagador) lo decide el propietario.
-- Requiere 0030. Idempotente.

-- ---------- Datos de los pagos ----------
alter table plone27_checkouts add column if not exists medio text not null default 'cuenta' check(medio in('cuenta','tarjeta'));
alter table plone27_checkouts add column if not exists tarjeta uuid references plone27_cards(id);
alter table plone27_checkouts add column if not exists interbancaria boolean not null default false;
alter table plone27_checkouts add column if not exists comision numeric(18,2) not null default 0 check(comision>=0);
alter table plone27_checkouts add column if not exists comision_pagador text not null default 'cliente' check(comision_pagador in('cliente','banco'));
alter table plone27_checkouts add column if not exists comision_beneficiario text not null default 'propietario' check(comision_beneficiario in('propietario','banco_pagador'));

-- ---------- Tarifa por banco (la fija el propietario de la pasarela) ----------
create table if not exists plone27_comisiones_banco(
  bank_id uuid primary key references plone27_banks,
  beneficiario text not null default 'propietario' check(beneficiario in('propietario','banco_pagador')),
  tipo text not null default 'fijo' check(tipo in('fijo','porcentaje')),
  valor numeric(18,4) not null default 0 check(valor>=0),
  actualizado timestamptz not null default now());

-- ---------- Política del banco: quién paga la comisión, para cuenta y para tarjeta ----------
create table if not exists plone27_politica_comision(
  bank_id uuid not null references plone27_banks,
  producto text not null check(producto in('cuenta','tarjeta')),
  pagador text not null default 'cliente' check(pagador in('cliente','banco')),
  primary key(bank_id,producto));

create or replace function plone27_comision_calc(p_bank uuid,p_importe numeric) returns numeric
language sql stable security definer set search_path=public as $$
  select coalesce((select case when c.tipo='fijo' then round(c.valor,2) else round(p_importe*c.valor/100,2) end
    from plone27_comisiones_banco c where c.bank_id=p_bank),0) $$;

-- Cuenta de comisiones del banco (se abre la primera vez)
create or replace function plone27_comision_cuenta(p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  select a.id into cid from plone27_accounts a
    where a.bank_id=p_bank and a.kind='system' and a.name='Comisiones interbancarias' limit 1;
  if cid is null then
    cid:=(plone27_open_account(p_bank,'system','Comisiones interbancarias',null,null)->>'id')::uuid;
  end if;
  return cid; end $$;

-- Política del banco (lo llama la API del banco)
create or replace function plone27_bk_politica_set(p_bank uuid,p_producto text,p_pagador text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  insert into plone27_politica_comision(bank_id,producto,pagador) values(p_bank,p_producto,p_pagador)
    on conflict(bank_id,producto) do update set pagador=excluded.pagador;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'comision_politica','bank',p_bank::text,jsonb_build_object('producto',p_producto,'pagador',p_pagador));
end $$;

-- Tarifa del banco (lo fija el propietario desde el panel)
create or replace function plone27_admin_comision_set(p_bank uuid,p_beneficiario text,p_tipo text,p_valor numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  insert into plone27_comisiones_banco(bank_id,beneficiario,tipo,valor) values(p_bank,p_beneficiario,p_tipo,p_valor)
    on conflict(bank_id) do update set beneficiario=excluded.beneficiario, tipo=excluded.tipo, valor=excluded.valor, actualizado=now();
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'comision_tarifa','bank',p_bank::text,jsonb_build_object('beneficiario',p_beneficiario,'tipo',p_tipo,'valor',p_valor));
end $$;

-- ---------- Crear un pago: cuenta o tarjeta, con la comisión calculada si es interbancario ----------
drop function if exists plone27_checkout_create(uuid,uuid,text,text,text,text,text,numeric,text,text,text,integer);
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_tarjeta_ref text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; pagador uuid; tarj plone27_cards; medio text:='cuenta'; destino uuid; dbank uuid; inter boolean:=false;
  com numeric:=0; pagad text:='cliente'; benef text:='propietario'; cid uuid; caduca timestamptz; mins int:=coalesce(p_minutos,15); begin
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>50000 then raise exception 'Importe entre 0,01 y 50.000 Pz'; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if coalesce(length(p_codigo),0)<>6 then raise exception 'Código de verificación no válido'; end if;
  if (coalesce(p_iban_pagador,'')='') = (coalesce(p_tarjeta_ref,'')='') then raise exception 'Indica una cuenta o una tarjeta, no las dos ni ninguna'; end if;
  pid:=plone27_persona(p_dip);
  if coalesce(p_tarjeta_ref,'')<>'' then
    select cd.* into tarj from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
      where cd.card_ref=p_tarjeta_ref and a.bank_id=p_bank;
    if tarj.id is null or tarj.status<>'active' then raise exception 'Tarjeta no válida o no activa'; end if;
    if not plone27_user_can(pid,tarj.account_id,true,p_bank) then raise exception 'La tarjeta no es accesible para esta persona'; end if;
    pagador:=tarj.account_id; medio:='tarjeta';
  else
    select a.id into pagador from plone27_accounts a where a.iban=p_iban_pagador and a.bank_id=p_bank;
    if pagador is null or not plone27_user_can(pid,pagador,true,p_bank) then raise exception 'Cuenta del pagador no accesible'; end if;
  end if;
  select a.id into destino from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  select a.bank_id into dbank from plone27_accounts a where a.id=destino;
  inter:=dbank<>p_bank;
  if inter then
    com:=plone27_comision_calc(p_bank,p_importe);
    select coalesce((select pc.pagador from plone27_politica_comision pc where pc.bank_id=p_bank and pc.producto=medio),'cliente') into pagad;
    select coalesce((select cb.beneficiario from plone27_comisiones_banco cb where cb.bank_id=p_bank),'propietario') into benef;
  end if;
  caduca:=now()+make_interval(mins=>mins);
  insert into plone27_checkouts(token_hash,bank_id,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
      importe,concepto,codigo_hash,codigo_expira,expira_at,medio,tarjeta,interbancaria,comision,comision_pagador,comision_beneficiario)
    values(plone27_sha(p_token),p_bank,p_client,lower(p_origen),p_client_ref,pid,pagador,destino,p_importe,p_concepto,
      plone27_sha(p_codigo),caduca,caduca,medio,case when medio='tarjeta' then tarj.id else null end,inter,com,pagad,benef)
    returning plone27_checkouts.id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.codigo',array[p_bank],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'codigo',p_codigo,'importe',p_importe,'concepto',p_concepto,
      'comision',com,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca,'comision',com,
    'total',case when pagad='cliente' then p_importe+com else p_importe end);
end $$;

-- ---------- Estado público: añade medio, comisión y total ----------
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'intentos_restantes',greatest(0,3-c.intentos),
    'origen',c.origen_banco,'banco',jsonb_build_object('nombre',b.name,'logo',b.logo_url,'color',b.color_principal),
    'comercio',cl.name,'medio',c.medio,'comision',c.comision,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end)
  from plone27_checkouts c join plone27_banks b on b.id=c.bank_id join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

-- ---------- Confirmar: cobra con cuenta o con tarjeta, y reparte la comisión ----------
create or replace function plone27_checkout_confirm(p_token text,p_codigo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; tx uuid; ch uuid; ch2 uuid; tarj plone27_cards; ben_acc uuid; orig_acc uuid; begin
  select * into c from plone27_checkouts where token_hash=plone27_sha(p_token) for update;
  if c.id is null then return jsonb_build_object('ok',false,'error','Pago no encontrado'); end if;
  if c.estado<>'pendiente' then return jsonb_build_object('ok',false,'error','Este pago ya no está pendiente','estado',c.estado); end if;
  if c.expira_at<now() then
    update plone27_checkouts set estado='caducado',resuelta=now() where id=c.id;
    return jsonb_build_object('ok',false,'error','El pago ha caducado','estado','caducado');
  end if;
  if c.codigo_hash<>plone27_sha(coalesce(p_codigo,'')) then
    update plone27_checkouts set intentos=intentos+1,
      estado=case when intentos+1>=3 then 'fallido' else estado end,
      resuelta=case when intentos+1>=3 then now() else resuelta end
      where id=c.id;
    return jsonb_build_object('ok',false,'error','Código incorrecto',
      'intentos_restantes',greatest(0,2-c.intentos),
      'estado',case when c.intentos+1>=3 then 'fallido' else 'pendiente' end);
  end if;
  begin
    ben_acc:=case when c.comision_beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(c.bank_id) end;
    orig_acc:=case when c.comision_pagador='cliente' then c.pagador_cuenta else plone27_comision_cuenta(c.bank_id) end;
    if c.medio='tarjeta' then
      select * into tarj from plone27_cards where id=c.tarjeta;
      if tarj.kind='prepago' then ch:=plone27_prepago_authorize(tarj.id,c.importe,c.cuenta_destino);
      else ch:=plone27_card_authorize(tarj.id,c.importe,c.cuenta_destino,null); end if;
      tx:=plone27_card_settle('checkout:'||c.id::text,ch,null);
      if c.comision>0 then
        if c.comision_pagador='cliente' then
          if tarj.kind='prepago' then ch2:=plone27_prepago_authorize(tarj.id,c.comision,ben_acc);
          else ch2:=plone27_card_authorize(tarj.id,c.comision,ben_acc,null); end if;
          perform plone27_card_settle('checkout-com:'||c.id::text,ch2,null);
        elsif orig_acc<>ben_acc then
          perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
        end if;
      end if;
    else
      tx:=plone27_transfer('checkout:'||c.id::text,c.pagador_cuenta,c.cuenta_destino,c.importe,c.concepto,null);
      if c.comision>0 and orig_acc<>ben_acc then
        perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
      end if;
    end if;
  exception when others then
    return jsonb_build_object('ok',false,'error',sqlerrm,'estado','pendiente');
  end;
  update plone27_checkouts set estado='pagado',tx=tx,resuelta=now() where id=c.id;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.pagado',array[c.bank_id],
    jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'importe',c.importe,'comision',c.comision,'transaccion',tx));
  return jsonb_build_object('ok',true,'transaccion',tx,'estado','pagado');
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

-- ==================== MIGRACIÓN (0032_plone27_confirmacion_banco_pagador.sql) ====================
-- Placeta One · 0032 · La confirmación del pago la realiza el banco de quien paga.
-- El pago puede ser de cualquier banco. Placeta avisa al banco pagador (checkout.confirmacion_requerida)
-- y ejecuta el cobro cuando el banco pagador aprueba. Ya no hay código de verificación en Placeta.
-- Requiere 0031. Idempotente.

-- ---------- Banco pagador ----------
alter table plone27_checkouts add column if not exists banco_pagador uuid references plone27_banks;
update plone27_checkouts set banco_pagador=bank_id where banco_pagador is null;
alter table plone27_checkouts alter column banco_pagador set not null;

-- El código de verificación ya no existe en Placeta
alter table plone27_checkouts alter column codigo_hash drop not null;
alter table plone27_checkouts alter column codigo_expira drop not null;

-- Estado nuevo: rechazado por el banco pagador
alter table plone27_checkouts drop constraint if exists plone27_checkouts_estado_check,
  add constraint plone27_checkouts_estado_check check(estado in('pendiente','pagado','fallido','cancelado','caducado','rechazado')) not valid;

-- Los pagos pendientes del sistema anterior (con código de Placeta) no se pueden confirmar: se cancelan
update plone27_checkouts set estado='cancelado', resuelta=now() where estado='pendiente';

drop function if exists plone27_checkout_create(uuid,uuid,text,text,text,text,text,text,numeric,text,text,text,integer);
drop function if exists plone27_checkout_confirm(text,text);

-- ---------- Crear un pago: el pagador se identifica por cuenta o tarjeta de cualquier banco ----------
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_tarjeta_ref text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; pagador uuid; tarj plone27_cards; medio text:='cuenta'; destino uuid; dbank uuid; bpag uuid; inter boolean:=false;
  com numeric:=0; pagad text:='cliente'; benef text:='propietario'; cid uuid; caduca timestamptz; mins int:=coalesce(p_minutos,15); nombre_comercio text; begin
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>50000 then raise exception 'Importe entre 0,01 y 50.000 Pz'; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if (coalesce(p_iban_pagador,'')='') = (coalesce(p_tarjeta_ref,'')='') then raise exception 'Indica una cuenta o una tarjeta, no las dos ni ninguna'; end if;
  pid:=plone27_persona(p_dip);
  if coalesce(p_tarjeta_ref,'')<>'' then
    select cd.* into tarj from plone27_cards cd where cd.card_ref=p_tarjeta_ref;
    if tarj.id is null or tarj.status<>'active' then raise exception 'Tarjeta no válida o no activa'; end if;
    select a.bank_id into bpag from plone27_accounts a where a.id=tarj.account_id;
    if not plone27_user_can(pid,tarj.account_id,true,bpag) then raise exception 'La tarjeta no es accesible para esta persona'; end if;
    pagador:=tarj.account_id; medio:='tarjeta';
  else
    select a.id, a.bank_id into pagador, bpag from plone27_accounts a where a.iban=p_iban_pagador and a.status='active';
    if pagador is null or not plone27_user_can(pid,pagador,true,bpag) then raise exception 'Cuenta del pagador no accesible'; end if;
  end if;
  select a.id into destino from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  select a.bank_id into dbank from plone27_accounts a where a.id=destino;
  inter:=dbank<>bpag;
  if inter then
    com:=plone27_comision_calc(bpag,p_importe);
    select coalesce((select pc.pagador from plone27_politica_comision pc where pc.bank_id=bpag and pc.producto=medio),'cliente') into pagad;
    select coalesce((select cb.beneficiario from plone27_comisiones_banco cb where cb.bank_id=bpag),'propietario') into benef;
  end if;
  select cl.name into nombre_comercio from plone27_api_clients cl where cl.id=p_client;
  caduca:=now()+make_interval(mins=>mins);
  insert into plone27_checkouts(token_hash,bank_id,banco_pagador,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
      importe,concepto,codigo_hash,codigo_expira,expira_at,medio,tarjeta,interbancaria,comision,comision_pagador,comision_beneficiario)
    values(plone27_sha(p_token),p_bank,bpag,p_client,lower(p_origen),p_client_ref,pid,pagador,destino,p_importe,p_concepto,
      null,caduca,caduca,medio,case when medio='tarjeta' then tarj.id else null end,inter,com,pagad,benef)
    returning plone27_checkouts.id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.confirmacion_requerida',array[bpag],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'comercio',nombre_comercio,'importe',p_importe,'concepto',p_concepto,
      'comision',com,'medio',medio,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca,'comision',com,
    'total',case when pagad='cliente' then p_importe+com else p_importe end);
end $$;

-- Estado público para la ventana de pago: muestra el banco pagador (su logo y colores) y si espera su confirmación
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'origen',c.origen_banco,
    'banco',jsonb_build_object('nombre',b.name,'logo',b.logo_url,'color',b.color_principal),
    'comercio',cl.name,'medio',c.medio,'comision',c.comision,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end)
  from plone27_checkouts c join plone27_banks b on b.id=c.banco_pagador join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

-- Pagos pendientes de confirmación para el banco pagador
create or replace function plone27_bk_pagos_pendientes(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada),'[]'::jsonb) from (
    select c.id, c.client_ref, c.importe, c.concepto, c.comision, c.comision_pagador, c.medio, c.expira_at as expira, c.creada
    from plone27_checkouts c
    where c.banco_pagador=p_bank and c.estado='pendiente' and c.expira_at>now()) x $$;

-- Resolución del banco pagador: aprobar (ejecuta el cobro) o rechazar
create or replace function plone27_checkout_resolver(p_checkout uuid,p_bank_pagador uuid,p_dip text,p_decision text,p_motivo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; pid uuid; tx uuid; ch uuid; ch2 uuid; tarj plone27_cards; ben_acc uuid; orig_acc uuid; begin
  select * into c from plone27_checkouts where id=p_checkout for update;
  if c.id is null or c.banco_pagador<>p_bank_pagador then raise exception 'Pago no encontrado'; end if;
  if c.estado<>'pendiente' then raise exception 'Este pago ya no está pendiente (%)', c.estado; end if;
  if c.expira_at<now() then
    update plone27_checkouts set estado='caducado', resuelta=now() where id=c.id;
    return jsonb_build_object('estado','caducado');
  end if;
  if p_decision not in('aprobado','rechazado') then raise exception 'Decisión no válida'; end if;
  pid:=plone27_persona(p_dip);
  if not plone27_user_can(pid,c.pagador_cuenta,true,c.banco_pagador) then raise exception 'La persona no puede autorizar esta cuenta'; end if;
  if p_decision='rechazado' then
    update plone27_checkouts set estado='rechazado', resuelta=now() where id=c.id;
    insert into plone27_outbox(event,bank_ids,payload) values('checkout.rechazado',array[c.bank_id],
      jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'motivo',p_motivo));
    return jsonb_build_object('estado','rechazado');
  end if;
  begin
    ben_acc:=case when c.comision_beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(c.banco_pagador) end;
    orig_acc:=case when c.comision_pagador='cliente' then c.pagador_cuenta else plone27_comision_cuenta(c.banco_pagador) end;
    if c.medio='tarjeta' then
      select * into tarj from plone27_cards where id=c.tarjeta;
      if tarj.kind='prepago' then ch:=plone27_prepago_authorize(tarj.id,c.importe,c.cuenta_destino);
      else ch:=plone27_card_authorize(tarj.id,c.importe,c.cuenta_destino,null); end if;
      tx:=plone27_card_settle('checkout:'||c.id::text,ch,null);
      if c.comision>0 then
        if c.comision_pagador='cliente' then
          if tarj.kind='prepago' then ch2:=plone27_prepago_authorize(tarj.id,c.comision,ben_acc);
          else ch2:=plone27_card_authorize(tarj.id,c.comision,ben_acc,null); end if;
          perform plone27_card_settle('checkout-com:'||c.id::text,ch2,null);
        elsif orig_acc<>ben_acc then
          perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
        end if;
      end if;
    else
      tx:=plone27_transfer('checkout:'||c.id::text,c.pagador_cuenta,c.cuenta_destino,c.importe,c.concepto,null);
      if c.comision>0 and orig_acc<>ben_acc then
        perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
      end if;
    end if;
  exception when others then
    return jsonb_build_object('estado','pendiente','error',sqlerrm);
  end;
  update plone27_checkouts set estado='pagado', tx=tx, resuelta=now() where id=c.id;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.pagado',
    case when c.bank_id=c.banco_pagador then array[c.bank_id] else array[c.bank_id,c.banco_pagador] end,
    jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'importe',c.importe,'comision',c.comision,'transaccion',tx));
  return jsonb_build_object('estado','pagado','transaccion',tx);
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

-- ==================== MIGRACIÓN (0033_plone27_pasarela_producto_codigo.sql) ====================
-- Placeta One · 0033 · La pasarela es un producto por banco para cuentas de empresa e institucionales.
-- Código de pago que el banco del pagador canjea en su propia app. Restricciones por banco (medios, tipos de tarjeta,
-- modalidades y operaciones). Aviso de comisiones. Requiere 0032. Idempotente.

-- ---------- Código de pago ----------
create unique index if not exists plone27_checkouts_codigo_ux on plone27_checkouts(codigo_hash);

-- ---------- Restricciones que cada banco aplica a sus clientes ----------
create table if not exists plone27_restricciones_pago(
  bank_id uuid not null references plone27_banks,
  tipo text not null check(tipo in('medio','tarjeta','modalidad','operacion')),
  valor text not null,
  bloqueado boolean not null default true,
  actualizado timestamptz not null default now(),
  primary key(bank_id,tipo,valor));

create or replace function plone27_restriccion_activa(p_bank uuid,p_tipo text,p_valor text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_restricciones_pago r
    where r.bank_id=p_bank and r.tipo=p_tipo and r.valor=p_valor and r.bloqueado) $$;

-- Motivo por el que el banco no permite el pago, o nulo si está permitido
create or replace function plone27_checkout_bloqueado(p_bank uuid,p_medio text,p_tkind text,p_inter boolean) returns text
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_medio='cuenta' and plone27_restriccion_activa(p_bank,'medio','cuenta') then return 'Tu banco no permite pagos desde cuenta'; end if;
  if p_medio='tarjeta' and plone27_restriccion_activa(p_bank,'medio','tarjeta') then return 'Tu banco no permite pagos con tarjeta'; end if;
  if p_medio='tarjeta' and plone27_restriccion_activa(p_bank,'tarjeta',p_tkind) then return 'Tu banco no permite este tipo de tarjeta'; end if;
  if p_medio='tarjeta' and p_tkind='credit' and plone27_restriccion_activa(p_bank,'modalidad','diferida') then return 'Tu banco no permite pagos diferidos'; end if;
  if p_medio='tarjeta' and p_tkind<>'credit' and plone27_restriccion_activa(p_bank,'modalidad','inmediata') then return 'Tu banco no permite pagos inmediatos con tarjeta'; end if;
  if p_inter and plone27_restriccion_activa(p_bank,'operacion','interbancario') then return 'Tu banco no permite pagos interbancarios'; end if;
  return null; end $$;

-- El banco activa o desactiva una restricción (valores permitidos fijos)
create or replace function plone27_bk_restriccion_set(p_bank uuid,p_tipo text,p_valor text,p_bloqueado boolean) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not((p_tipo='medio' and p_valor in('cuenta','tarjeta'))
      or (p_tipo='tarjeta' and p_valor in('digital','physical','credit','prepago'))
      or (p_tipo='modalidad' and p_valor in('inmediata','diferida'))
      or (p_tipo='operacion' and p_valor='interbancario')) then
    raise exception 'Restricción no válida';
  end if;
  insert into plone27_restricciones_pago(bank_id,tipo,valor,bloqueado) values(p_bank,p_tipo,p_valor,p_bloqueado)
    on conflict(bank_id,tipo,valor) do update set bloqueado=excluded.bloqueado, actualizado=now();
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'restriccion_pago','bank',p_bank::text,jsonb_build_object('tipo',p_tipo,'valor',p_valor,'bloqueado',p_bloqueado));
end $$;

-- Texto de aviso: solo cuando hay comisión visible
create or replace function plone27_aviso_comisiones() returns text
language sql immutable as $$
  select 'Tu entidad de pagos del ecosistema Placeta puede aplicar otras comisiones extra a las mostradas.' $$;

-- ---------- Crear el pago con código ----------
drop function if exists plone27_checkout_create(uuid,uuid,text,text,text,text,text,text,numeric,text,text,integer);
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_tarjeta_ref text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo_pago text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; pagador uuid; tarj plone27_cards; medio text:='cuenta'; destino uuid; dbank uuid; dkind text; bpag uuid; inter boolean:=false;
  com numeric:=0; pagad text:='cliente'; benef text:='propietario'; cid uuid; caduca timestamptz; mins int:=coalesce(p_minutos,15);
  nombre_comercio text; motivo text; begin
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>50000 then raise exception 'Importe entre 0,01 y 50.000 Pz'; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if length(replace(coalesce(p_codigo_pago,''),'-',''))<>16 then raise exception 'Código de pago no válido'; end if;
  if (coalesce(p_iban_pagador,'')='') = (coalesce(p_tarjeta_ref,'')='') then raise exception 'Indica una cuenta o una tarjeta, no las dos ni ninguna'; end if;
  pid:=plone27_persona(p_dip);
  if coalesce(p_tarjeta_ref,'')<>'' then
    select cd.* into tarj from plone27_cards cd where cd.card_ref=p_tarjeta_ref;
    if tarj.id is null or tarj.status<>'active' then raise exception 'Tarjeta no válida o no activa'; end if;
    select a.bank_id into bpag from plone27_accounts a where a.id=tarj.account_id;
    if not plone27_user_can(pid,tarj.account_id,true,bpag) then raise exception 'La tarjeta no es accesible para esta persona'; end if;
    pagador:=tarj.account_id; medio:='tarjeta';
  else
    select a.id, a.bank_id into pagador, bpag from plone27_accounts a where a.iban=p_iban_pagador and a.status='active';
    if pagador is null or not plone27_user_can(pid,pagador,true,bpag) then raise exception 'Cuenta del pagador no accesible'; end if;
  end if;
  select a.id, a.kind, a.bank_id into destino, dkind, dbank from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  if dkind not in('business','system') then raise exception 'La pasarela solo cobra a cuentas de empresa o institucionales'; end if;
  inter:=dbank<>bpag;
  motivo:=plone27_checkout_bloqueado(bpag,medio,case when medio='tarjeta' then tarj.kind else null end,inter);
  if motivo is not null then raise exception '%', motivo; end if;
  if inter then
    com:=plone27_comision_calc(bpag,p_importe);
    select coalesce((select pc.pagador from plone27_politica_comision pc where pc.bank_id=bpag and pc.producto=medio),'cliente') into pagad;
    select coalesce((select cb.beneficiario from plone27_comisiones_banco cb where cb.bank_id=bpag),'propietario') into benef;
  end if;
  select cl.name into nombre_comercio from plone27_api_clients cl where cl.id=p_client;
  caduca:=now()+make_interval(mins=>mins);
  insert into plone27_checkouts(token_hash,bank_id,banco_pagador,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
      importe,concepto,codigo_hash,codigo_expira,expira_at,medio,tarjeta,interbancaria,comision,comision_pagador,comision_beneficiario)
    values(plone27_sha(p_token),p_bank,bpag,p_client,lower(p_origen),p_client_ref,pid,pagador,destino,p_importe,p_concepto,
      plone27_sha(upper(replace(p_codigo_pago,'-',''))),caduca,caduca,medio,case when medio='tarjeta' then tarj.id else null end,inter,com,pagad,benef)
    returning plone27_checkouts.id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.confirmacion_requerida',array[bpag],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'comercio',nombre_comercio,'importe',p_importe,'concepto',p_concepto,
      'comision',com,'medio',medio,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca,'comision',com,
    'total',case when pagad='cliente' then p_importe+com else p_importe end,
    'aviso',case when com>0 then plone27_aviso_comisiones() else null end);
end $$;

-- ---------- El banco canjea el código en su app: ve el pago antes de aprobarlo ----------
create or replace function plone27_checkout_por_codigo(p_bank uuid,p_codigo text,p_dip text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; pid uuid; motivo text; begin
  select * into c from plone27_checkouts where codigo_hash=plone27_sha(upper(replace(coalesce(p_codigo,''),'-','')));
  if c.id is null or c.banco_pagador<>p_bank then raise exception 'Código no válido para tu entidad'; end if;
  if c.estado<>'pendiente' or c.expira_at<now() then raise exception 'El código ya no es válido'; end if;
  pid:=plone27_persona(p_dip);
  if not plone27_user_can(pid,c.pagador_cuenta,true,p_bank) then raise exception 'La persona no puede autorizar esta cuenta'; end if;
  motivo:=plone27_checkout_bloqueado(p_bank,c.medio,case when c.medio='tarjeta' then (select cd.kind from plone27_cards cd where cd.id=c.tarjeta) else null end,c.interbancaria);
  return jsonb_build_object('checkout_id',c.id,
    'comercio',(select cl.name from plone27_api_clients cl where cl.id=c.client_id),
    'importe',c.importe,'concepto',c.concepto,'medio',c.medio,'comision',c.comision,'comision_pagador',c.comision_pagador,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end,
    'aviso',case when c.comision>0 then plone27_aviso_comisiones() else null end,
    'expira',c.expira_at,
    'origen_pago',case when c.medio='tarjeta' then jsonb_build_object('tarjeta_ultimos4',(select cd.last4 from plone27_cards cd where cd.id=c.tarjeta))
                       else jsonb_build_object('iban',(select a.iban from plone27_accounts a where a.id=c.pagador_cuenta)) end,
    'bloqueado',motivo);
end $$;

-- ---------- Estado público: añade el aviso ----------
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'origen',c.origen_banco,
    'banco',jsonb_build_object('nombre',b.name,'logo',b.logo_url,'color',b.color_principal),
    'comercio',cl.name,'medio',c.medio,'comision',c.comision,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end,
    'aviso',case when c.comision>0 then plone27_aviso_comisiones() else null end)
  from plone27_checkouts c join plone27_banks b on b.id=c.banco_pagador join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

-- ---------- Resolución: el banco aprueba; se vuelve a comprobar la restricción por si cambió ----------
create or replace function plone27_checkout_resolver(p_checkout uuid,p_bank_pagador uuid,p_dip text,p_decision text,p_motivo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; pid uuid; tx uuid; ch uuid; ch2 uuid; tarj plone27_cards; ben_acc uuid; orig_acc uuid; bloq text; begin
  select * into c from plone27_checkouts where id=p_checkout for update;
  if c.id is null or c.banco_pagador<>p_bank_pagador then raise exception 'Pago no encontrado'; end if;
  if c.estado<>'pendiente' then raise exception 'Este pago ya no está pendiente (%)', c.estado; end if;
  if c.expira_at<now() then
    update plone27_checkouts set estado='caducado', resuelta=now() where id=c.id;
    return jsonb_build_object('estado','caducado');
  end if;
  if p_decision not in('aprobado','rechazado') then raise exception 'Decisión no válida'; end if;
  pid:=plone27_persona(p_dip);
  if not plone27_user_can(pid,c.pagador_cuenta,true,c.banco_pagador) then raise exception 'La persona no puede autorizar esta cuenta'; end if;
  if p_decision='rechazado' then
    update plone27_checkouts set estado='rechazado', resuelta=now() where id=c.id;
    insert into plone27_outbox(event,bank_ids,payload) values('checkout.rechazado',array[c.bank_id],
      jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'motivo',p_motivo));
    return jsonb_build_object('estado','rechazado');
  end if;
  bloq:=plone27_checkout_bloqueado(c.banco_pagador,c.medio,case when c.medio='tarjeta' then (select cd.kind from plone27_cards cd where cd.id=c.tarjeta) else null end,c.interbancaria);
  if bloq is not null then return jsonb_build_object('estado','pendiente','error',bloq); end if;
  begin
    ben_acc:=case when c.comision_beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(c.banco_pagador) end;
    orig_acc:=case when c.comision_pagador='cliente' then c.pagador_cuenta else plone27_comision_cuenta(c.banco_pagador) end;
    if c.medio='tarjeta' then
      select * into tarj from plone27_cards where id=c.tarjeta;
      if tarj.kind='prepago' then ch:=plone27_prepago_authorize(tarj.id,c.importe,c.cuenta_destino);
      else ch:=plone27_card_authorize(tarj.id,c.importe,c.cuenta_destino,null); end if;
      tx:=plone27_card_settle('checkout:'||c.id::text,ch,null);
      if c.comision>0 then
        if c.comision_pagador='cliente' then
          if tarj.kind='prepago' then ch2:=plone27_prepago_authorize(tarj.id,c.comision,ben_acc);
          else ch2:=plone27_card_authorize(tarj.id,c.comision,ben_acc,null); end if;
          perform plone27_card_settle('checkout-com:'||c.id::text,ch2,null);
        elsif orig_acc<>ben_acc then
          perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
        end if;
      end if;
    else
      tx:=plone27_transfer('checkout:'||c.id::text,c.pagador_cuenta,c.cuenta_destino,c.importe,c.concepto,null);
      if c.comision>0 and orig_acc<>ben_acc then
        perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
      end if;
    end if;
  exception when others then
    return jsonb_build_object('estado','pendiente','error',sqlerrm);
  end;
  update plone27_checkouts set estado='pagado', tx=tx, resuelta=now() where id=c.id;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.pagado',
    case when c.bank_id=c.banco_pagador then array[c.bank_id] else array[c.bank_id,c.banco_pagador] end,
    jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'importe',c.importe,'comision',c.comision,'transaccion',tx));
  return jsonb_build_object('estado','pagado','transaccion',tx);
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

-- ==================== MIGRACIÓN (0034_plone27_pasarela_producto_branding_webhooks.sql) ====================
-- Placeta One · 0034 · APIs de banco: producto pasarela con parámetros, branding, webhooks, cuentas y listado de pagos.
-- Requiere 0033. Idempotente.

-- ---------- Producto pasarela por banco ----------
create table if not exists plone27_pasarela_config(
  bank_id uuid primary key references plone27_banks,
  activa boolean not null default false,
  minutos_defecto int not null default 15 check(minutos_defecto between 3 and 30),
  importe_maximo numeric(18,2) not null default 50000 check(importe_maximo>0),
  destinos text[] not null default '{business,system}',
  actualizada timestamptz not null default now());

-- ---------- Branding ----------
alter table plone27_banks add column if not exists nombre_visible text check(nombre_visible is null or length(nombre_visible) between 2 and 80);
alter table plone27_banks add column if not exists texto_pie text check(texto_pie is null or length(texto_pie)<=200);
alter table plone27_api_clients add column if not exists logo_url text check(logo_url is null or logo_url ~ '^https://[^\s]+$');
alter table plone27_api_clients add column if not exists color_principal text check(color_principal is null or color_principal ~ '^#[0-9A-Fa-f]{6}$');
alter table plone27_api_clients add column if not exists nombre_comercial text check(nombre_comercial is null or length(nombre_comercial) between 2 and 80);

create or replace function plone27_bk_pasarela_set(p_bank uuid,p_activa boolean,p_minutos int,p_importe_max numeric,p_destinos text[]) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_destinos is null or array_length(p_destinos,1) is null or not(p_destinos <@ array['business','system']::text[]) then
    raise exception 'Destinos no válidos (business, system)';
  end if;
  insert into plone27_pasarela_config(bank_id,activa,minutos_defecto,importe_maximo,destinos)
    values(p_bank,coalesce(p_activa,false),coalesce(p_minutos,15),coalesce(p_importe_max,50000),p_destinos)
    on conflict(bank_id) do update set activa=excluded.activa, minutos_defecto=excluded.minutos_defecto,
      importe_maximo=excluded.importe_maximo, destinos=excluded.destinos, actualizada=now();
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'pasarela_config','bank',p_bank::text,jsonb_build_object('activa',p_activa,'importe_maximo',p_importe_max,'destinos',p_destinos));
end $$;

-- ---------- Branding ----------
create or replace function plone27_bk_branding_set(p_bank uuid,p_logo text,p_color text,p_nombre text,p_texto text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_banks set logo_url=p_logo, color_principal=p_color, nombre_visible=p_nombre, texto_pie=p_texto
            where id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Entidad no encontrada'; end if;
end $$;

create or replace function plone27_bk_branding_comercio_set(p_client uuid,p_bank uuid,p_logo text,p_color text,p_nombre text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_api_clients set logo_url=p_logo, color_principal=p_color, nombre_comercial=p_nombre
            where id=p_client and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Cliente no encontrado'; end if;
end $$;

-- ---------- Webhooks gestionados por el banco ----------
create or replace function plone27_bk_webhook_crear(p_bank uuid,p_url text,p_eventos text[],p_secret text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare wid uuid; begin
  if p_eventos is null or array_length(p_eventos,1) is null or not(p_eventos <@ array['*','checkout.confirmacion_requerida','checkout.pagado','checkout.rechazado','checkout.cancelado','gasto.propuesto','gasto.aprobado','gasto.rechazado','gasto.pagado','tarea.registrada','tarea.validada','tarea.rechazada','tarea.pagada','nomina.pagada','transaction.posted']::text[]) then
    raise exception 'Eventos no válidos';
  end if;
  insert into plone27_webhooks(bank_id,url,secret,events,active) values(p_bank,p_url,p_secret,p_eventos,true)
    returning plone27_webhooks.id into wid;
  return wid; end $$;

create or replace function plone27_bk_webhook_rotar(p_bank uuid,p_id uuid,p_secret text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_webhooks set secret=p_secret where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Webhook no encontrado'; end if;
end $$;

create or replace function plone27_bk_webhook_baja(p_bank uuid,p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(delete from plone27_webhooks where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Webhook no encontrado'; end if;
end $$;

-- ---------- Cuentas de la entidad con saldo disponible ----------
create or replace function plone27_bk_cuentas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.iban),'[]'::jsonb) from (
    select a.iban, a.name as nombre, a.kind as tipo, a.status as estado, plone27_available(a.id) as disponible
    from plone27_accounts a where a.bank_id=p_bank) x $$;

-- ---------- Pagos de un cliente de API ----------
create or replace function plone27_bk_checkouts_lista(p_client uuid,p_estado text,p_limite int) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select c.id, c.client_ref, c.estado, c.importe, c.concepto, c.comision, c.creada, c.resuelta as resuelto, c.expira_at as expira
    from plone27_checkouts c
    where c.client_id=p_client and (p_estado is null or c.estado=p_estado)
    order by c.creada desc limit least(greatest(coalesce(p_limite,50),1),200)) x $$;

-- ---------- Creación de pagos: comprueba el producto, sus parámetros y las restricciones ----------
drop function if exists plone27_checkout_create(uuid,uuid,text,text,text,text,text,text,numeric,text,text,text,integer);
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_tarjeta_ref text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo_pago text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pc plone27_pasarela_config; pid uuid; pagador uuid; tarj plone27_cards; medio text:='cuenta'; destino uuid; dbank uuid; dkind text; bpag uuid; inter boolean:=false;
  com numeric:=0; pagad text:='cliente'; benef text:='propietario'; cid uuid; caduca timestamptz; mins int;
  nombre_comercio text; motivo text; begin
  select * into pc from plone27_pasarela_config where bank_id=p_bank;
  if pc.bank_id is null or not pc.activa then raise exception 'La pasarela no está activa para tu entidad'; end if;
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>pc.importe_maximo then raise exception 'Importe entre 0,01 y % Pz', pc.importe_maximo; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  mins:=coalesce(p_minutos,pc.minutos_defecto);
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if length(replace(coalesce(p_codigo_pago,''),'-',''))<>16 then raise exception 'Código de pago no válido'; end if;
  if (coalesce(p_iban_pagador,'')='') = (coalesce(p_tarjeta_ref,'')='') then raise exception 'Indica una cuenta o una tarjeta, no las dos ni ninguna'; end if;
  pid:=plone27_persona(p_dip);
  if coalesce(p_tarjeta_ref,'')<>'' then
    select cd.* into tarj from plone27_cards cd where cd.card_ref=p_tarjeta_ref;
    if tarj.id is null or tarj.status<>'active' then raise exception 'Tarjeta no válida o no activa'; end if;
    select a.bank_id into bpag from plone27_accounts a where a.id=tarj.account_id;
    if not plone27_user_can(pid,tarj.account_id,true,bpag) then raise exception 'La tarjeta no es accesible para esta persona'; end if;
    pagador:=tarj.account_id; medio:='tarjeta';
  else
    select a.id, a.bank_id into pagador, bpag from plone27_accounts a where a.iban=p_iban_pagador and a.status='active';
    if pagador is null or not plone27_user_can(pid,pagador,true,bpag) then raise exception 'Cuenta del pagador no accesible'; end if;
  end if;
  select a.id, a.kind, a.bank_id into destino, dkind, dbank from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  if not(dkind = any(pc.destinos)) then raise exception 'La pasarela de tu entidad solo cobra a cuentas de tipo: %', array_to_string(pc.destinos,', '); end if;
  inter:=dbank<>bpag;
  motivo:=plone27_checkout_bloqueado(bpag,medio,case when medio='tarjeta' then tarj.kind else null end,inter);
  if motivo is not null then raise exception '%', motivo; end if;
  if inter then
    com:=plone27_comision_calc(bpag,p_importe);
    select coalesce((select pc2.pagador from plone27_politica_comision pc2 where pc2.bank_id=bpag and pc2.producto=medio),'cliente') into pagad;
    select coalesce((select cb.beneficiario from plone27_comisiones_banco cb where cb.bank_id=bpag),'propietario') into benef;
  end if;
  select cl.name into nombre_comercio from plone27_api_clients cl where cl.id=p_client;
  caduca:=now()+make_interval(mins=>mins);
  insert into plone27_checkouts(token_hash,bank_id,banco_pagador,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
      importe,concepto,codigo_hash,codigo_expira,expira_at,medio,tarjeta,interbancaria,comision,comision_pagador,comision_beneficiario)
    values(plone27_sha(p_token),p_bank,bpag,p_client,lower(p_origen),p_client_ref,pid,pagador,destino,p_importe,p_concepto,
      plone27_sha(upper(replace(p_codigo_pago,'-',''))),caduca,caduca,medio,case when medio='tarjeta' then tarj.id else null end,inter,com,pagad,benef)
    returning plone27_checkouts.id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.confirmacion_requerida',array[bpag],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'comercio',nombre_comercio,'importe',p_importe,'concepto',p_concepto,
      'comision',com,'medio',medio,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca,'comision',com,
    'total',case when pagad='cliente' then p_importe+com else p_importe end,
    'aviso',case when com>0 then plone27_aviso_comisiones() else null end);
end $$;

-- ---------- Estado público: branding del banco pagador y del comercio ----------
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'origen',c.origen_banco,
    'banco',jsonb_build_object('nombre',coalesce(b.nombre_visible,b.name),'logo',b.logo_url,'color',b.color_principal,'texto_pie',b.texto_pie),
    'comercio',coalesce(cl.nombre_comercial,cl.name),'comercio_logo',cl.logo_url,'comercio_color',cl.color_principal,
    'medio',c.medio,'comision',c.comision,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end,
    'aviso',case when c.comision>0 then plone27_aviso_comisiones() else null end)
  from plone27_checkouts c join plone27_banks b on b.id=c.banco_pagador join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

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

-- ==================== MIGRACIÓN (0035_plone27_entregas_reintento.sql) ====================
-- Placeta One · 0035 · Entregas de webhook con fechas e intentos, y reintento manual.
-- Un reintento devuelve el evento fallido a pendiente y pone sus intentos a cero; el envío automático lo vuelve a intentar.
-- Requiere 0034. Idempotente.

create or replace function plone27_bk_entrega_reintentar(p_bank uuid,p_id bigint) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_outbox set status='pending', attempts=0
            where id=p_id and status='failed' and p_bank=any(bank_ids) returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'La entrega no existe, no es de tu entidad o no está fallida'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'webhook_reintento','outbox',p_id::text,jsonb_build_object('bank',p_bank));
end $$;

create or replace function plone27_bk_entregas_lista(p_bank uuid,p_estado text,p_limite int) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id desc),'[]'::jsonb) from (
    select o.id, o.event as evento, o.status as estado, o.attempts as intentos, o.created_at as creada,
      coalesce(o.payload->>'checkout_id', o.payload->>'gasto', o.payload->>'tarea', o.payload->>'operation', o.payload->>'periodo') as referencia
    from plone27_outbox o
    where p_bank=any(o.bank_ids) and (p_estado is null or o.status=p_estado)
    order by o.id desc limit least(greatest(coalesce(p_limite,50),1),200)) x $$;

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

-- ==================== MIGRACIÓN (0036_plone27_empresas_pasarelas_nfc.sql) ====================
-- Placeta One · 0036 · Empresas (titulares y cuentas), pasarela por empresa con su propio cliente de API,
-- contratos versionados y identificadores NFC de tarjetas. Requiere 0035. Idempotente.

-- ---------- Empresas ----------
create table if not exists plone27_empresas(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks,
  nombre text not null check(length(nombre) between 2 and 120),
  identificador_fiscal text not null check(length(identificador_fiscal) between 5 and 20),
  estado text not null default 'activa' check(estado in('activa','suspendida','baja')),
  creada timestamptz not null default now(),
  unique(bank_id,identificador_fiscal));

create table if not exists plone27_empresa_cuentas(
  empresa_id uuid not null references plone27_empresas(id),
  account_id uuid not null references plone27_accounts,
  primary key(empresa_id,account_id));

create table if not exists plone27_empresa_titulares(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references plone27_empresas(id),
  persona uuid not null references plone27_personas,
  rol text not null check(rol in('titular','autorizado','lector')),
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  alta_por uuid,
  check(hasta is null or hasta>=desde));
create unique index if not exists plone27_empresa_titular_activo_ux on plone27_empresa_titulares(empresa_id,persona) where hasta is null;

-- ---------- Pasarela de la empresa: un cliente de API propio ----------
create table if not exists plone27_empresa_pasarelas(
  empresa_id uuid primary key references plone27_empresas(id),
  client_id uuid not null unique references plone27_api_clients,
  activa boolean not null default true,
  creada timestamptz not null default now());

-- ---------- Contratos versionados (sin claves) ----------
create table if not exists plone27_empresa_contratos(
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references plone27_empresas(id),
  version int not null check(version>=1),
  texto text not null check(length(texto)<=20000),
  creado timestamptz not null default now(),
  unique(empresa_id,version));

-- ---------- NFC de tarjetas (físicas o virtuales) ----------
alter table plone27_cards add column if not exists nfc_id text check(nfc_id is null or nfc_id ~ '^[A-Za-z0-9:_-]{8,64}$');
alter table plone27_cards add column if not exists nfc_enlace text check(nfc_enlace is null or nfc_enlace ~ '^https://[^\s]+$');
alter table plone27_cards add column if not exists nfc_actualizado timestamptz;
create unique index if not exists plone27_cards_nfc_id_ux on plone27_cards(nfc_id);

-- ---------- Las empresas solo cobran a sus propias cuentas (regla de base de datos) ----------
create or replace function plone27_trg_checkout_empresa() returns trigger
language plpgsql set search_path=public as $$
#variable_conflict use_column
declare emp uuid; begin
  select pe.empresa_id into emp from plone27_empresa_pasarelas pe where pe.client_id=new.client_id and pe.activa;
  if emp is not null and not exists(select 1 from plone27_empresa_cuentas ec where ec.empresa_id=emp and ec.account_id=new.cuenta_destino) then
    raise exception 'Esta pasarela solo cobra a las cuentas de su empresa';
  end if;
  return new; end $$;
drop trigger if exists trg_checkout_empresa on plone27_checkouts;
drop trigger if exists trg_checkout_empresa on plone27_checkouts;
create trigger trg_checkout_empresa before insert on plone27_checkouts
  for each row execute function plone27_trg_checkout_empresa();

-- ---------- Funciones de gestión ----------
create or replace function plone27_empresa_alta_completa(p_bank uuid,p_nombre text,p_fiscal text,p_persona uuid,p_ibans text[],p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare eid uuid; v_iban text; v_aid uuid; begin
  insert into plone27_empresas(bank_id,nombre,identificador_fiscal) values(p_bank,p_nombre,upper(p_fiscal))
    returning plone27_empresas.id into eid;
  foreach v_iban in array coalesce(p_ibans,'{}'::text[]) loop
    select a.id into v_aid from plone27_accounts a where a.iban=v_iban and a.bank_id=p_bank and a.kind='business' and a.status='active';
    if v_aid is null then raise exception 'La cuenta % no es una cuenta de empresa activa de tu entidad', v_iban; end if;
    insert into plone27_empresa_cuentas(empresa_id,account_id) values(eid,v_aid) on conflict do nothing;
  end loop;
  insert into plone27_empresa_titulares(empresa_id,persona,rol,motivo,alta_por)
    values(eid,p_persona,'titular','Alta de la empresa',p_actor);
  insert into plone27_account_members(account_id,user_id,role)
    select ec.account_id,p_persona,'holder' from plone27_empresa_cuentas ec where ec.empresa_id=eid on conflict do nothing;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_alta','empresa',eid::text,jsonb_build_object('fiscal',upper(p_fiscal)));
  return eid; end $$;

create or replace function plone27_empresa_titular_alta(p_bank uuid,p_empresa uuid,p_persona uuid,p_rol text,p_motivo text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare tid uuid; activos int; mrole text; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank and e.estado='activa') then
    raise exception 'Empresa no encontrada o no activa';
  end if;
  if p_rol not in('titular','autorizado','lector') then raise exception 'Rol no válido'; end if;
  select count(*) into activos from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.rol='titular' and t.hasta is null;
  if activos>0 and not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede dar altas';
  end if;
  insert into plone27_empresa_titulares(empresa_id,persona,rol,motivo,alta_por)
    values(p_empresa,p_persona,p_rol,p_motivo,p_actor) returning plone27_empresa_titulares.id into tid;
  mrole:=case p_rol when 'titular' then 'holder' when 'autorizado' then 'coholder' else 'authorized' end;
  insert into plone27_account_members(account_id,user_id,role)
    select ec.account_id,p_persona,mrole from plone27_empresa_cuentas ec where ec.empresa_id=p_empresa on conflict do nothing;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_titular_alta','empresa',p_empresa::text,jsonb_build_object('rol',p_rol));
  return tid; end $$;

create or replace function plone27_empresa_titular_cese(p_bank uuid,p_empresa uuid,p_persona uuid,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare activos int; n int; era_titular boolean; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank) then raise exception 'Empresa no encontrada'; end if;
  select count(*) into activos from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.rol='titular' and t.hasta is null;
  era_titular:=exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_persona and t.rol='titular' and t.hasta is null);
  if era_titular and activos<=1 then raise exception 'La empresa necesita al menos un titular'; end if;
  with x as(update plone27_empresa_titulares set hasta=current_date
            where empresa_id=p_empresa and persona=p_persona and hasta is null returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'La persona no es titular activo de la empresa'; end if;
  delete from plone27_account_members m using plone27_empresa_cuentas ec
    where ec.empresa_id=p_empresa and m.account_id=ec.account_id and m.user_id=p_persona;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_titular_cese','empresa',p_empresa::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- Pasarela de la empresa: crea su cliente de API con permisos de una lista cerrada
create or replace function plone27_empresa_pasarela_registrar(p_bank uuid,p_empresa uuid,p_nombre text,p_key_hash text,p_scopes text[],p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank and e.estado='activa') then
    raise exception 'Empresa no encontrada o no activa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede dar de alta su pasarela';
  end if;
  if exists(select 1 from plone27_empresa_pasarelas pe where pe.empresa_id=p_empresa and pe.activa) then
    raise exception 'La empresa ya tiene una pasarela activa';
  end if;
  if p_scopes is null or array_length(p_scopes,1) is null or not(p_scopes <@ array['checkout:crear','branding:gestionar','webhooks:gestionar','origenes:gestionar','accounts:read']::text[]) then
    raise exception 'Permisos no permitidos para una pasarela de empresa';
  end if;
  insert into plone27_api_clients(bank_id,name,key_hash,scopes) values(p_bank,p_nombre,p_key_hash,p_scopes)
    returning plone27_api_clients.id into cid;
  insert into plone27_empresa_pasarelas(empresa_id,client_id) values(p_empresa,cid);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_pasarela_alta','empresa',p_empresa::text,jsonb_build_object('client',cid,'scopes',p_scopes));
  return cid; end $$;

create or replace function plone27_empresa_contrato_guardar(p_bank uuid,p_empresa uuid,p_texto text) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v int; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank) then raise exception 'Empresa no encontrada'; end if;
  select coalesce(max(c.version),0)+1 into v from plone27_empresa_contratos c where c.empresa_id=p_empresa;
  insert into plone27_empresa_contratos(empresa_id,version,texto) values(p_empresa,v,p_texto);
  return v; end $$;

create or replace function plone27_empresa_contrato_actual(p_bank uuid,p_empresa uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('version',c.version,'texto',c.texto,'creado',c.creado)
  from plone27_empresa_contratos c join plone27_empresas e on e.id=c.empresa_id
  where c.empresa_id=p_empresa and e.bank_id=p_bank order by c.version desc limit 1 $$;

create or replace function plone27_empresa_detalle(p_bank uuid,p_empresa uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb; begin
  select jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado,
    'titulares',(select coalesce(jsonb_agg(jsonb_build_object('dip',p.dip,'rol',t.rol,'desde',t.desde,'hasta',t.hasta) order by t.desde),'[]'::jsonb)
                 from plone27_empresa_titulares t join plone27_personas p on p.id=t.persona where t.empresa_id=e.id),
    'cuentas',(select coalesce(jsonb_agg(jsonb_build_object('iban',a.iban,'nombre',a.name) order by a.iban),'[]'::jsonb)
               from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id where ec.empresa_id=e.id),
    'pasarela',(select jsonb_build_object('client_id',pe.client_id,'activa',pe.activa) from plone27_empresa_pasarelas pe where pe.empresa_id=e.id),
    'contrato_version',(select max(c.version) from plone27_empresa_contratos c where c.empresa_id=e.id))
  into r from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank;
  return r; end $$;

-- NFC: identificador y/o enlace de la tarjeta (física o virtual)
create or replace function plone27_tarjeta_nfc_set(p_bank uuid,p_ref text,p_nfc text,p_enlace text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_cards cd set nfc_id=nullif(p_nfc,''), nfc_enlace=nullif(p_enlace,''), nfc_actualizado=now()
            from plone27_accounts a
            where cd.card_ref=p_ref and a.id=cd.account_id and a.bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Tarjeta no encontrada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tarjeta_nfc','card',p_ref,jsonb_build_object('nfc',nullif(p_nfc,''),'enlace',nullif(p_enlace,'')));
end $$;

create or replace function plone27_tarjeta_nfc_get(p_bank uuid,p_ref text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('nfc_id',cd.nfc_id,'nfc_enlace',cd.nfc_enlace,'actualizado',cd.nfc_actualizado)
  from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
  where cd.card_ref=p_ref and a.bank_id=p_bank $$;

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

-- ==================== MIGRACIÓN (0037_plone27_tasas_interbancarias.sql) ====================
-- Placeta One · 0037 · Tasas configurables para pasarelas (por banco, por pasarela y por medio de pago),
-- aplicación automática al cobrar, operaciones interbancarias y posición neta frente a cada banco.
-- Requiere 0036. Idempotente.

-- ---------- Catálogo de tasas ----------
create table if not exists plone27_tasas(
  id uuid primary key default gen_random_uuid(),
  ambito text not null check(ambito in('propietario','banco')),
  bank_id uuid not null references plone27_banks,
  client_id uuid references plone27_api_clients,
  operacion text not null default 'pasarela_pago' check(operacion in('pasarela_pago')),
  medio text check(medio is null or medio in('cuenta','tarjeta')),
  tipo text not null check(tipo in('fijo','porcentaje')),
  valor numeric(18,4) not null check(valor>=0),
  minimo numeric(18,2) not null default 0 check(minimo>=0),
  maximo numeric(18,2) check(maximo is null or maximo>=minimo),
  pagador text not null check(pagador in('comercio','banco')),
  beneficiario text not null check(beneficiario in('propietario','banco')),
  activa boolean not null default true,
  creada timestamptz not null default now(),
  check(ambito='propietario' or (beneficiario='banco' and pagador='comercio')));

-- Registro de cada tasa cobrada (idempotente por pago y tasa)
create table if not exists plone27_tasas_cobradas(
  checkout uuid not null references plone27_checkouts(id),
  tasa uuid not null references plone27_tasas(id),
  importe numeric(18,2) not null check(importe>0),
  pagador text not null,
  beneficiario text not null,
  tx uuid,
  creada timestamptz not null default now(),
  primary key(checkout,tasa));

-- Tasas que aplican a un pago de la pasarela (importe calculado y acotado por mínimo y máximo)
create or replace function plone27_tasas_aplicables(p_bank uuid,p_client uuid,p_medio text,p_importe numeric)
returns table(tasa uuid,pagador text,beneficiario text,importe numeric)
language sql stable security definer set search_path=public as $$
  select t.id, t.pagador, t.beneficiario,
    round(least(greatest(case when t.tipo='fijo' then t.valor else p_importe*t.valor/100 end, t.minimo),
      coalesce(t.maximo,999999999999)),2)
  from plone27_tasas t
  where t.activa and t.bank_id=p_bank and t.operacion='pasarela_pago'
    and (t.medio is null or t.medio=p_medio)
    and (t.client_id is null or t.client_id=p_client) $$;

-- Cobro automático de las tasas cuando un pago de la pasarela queda pagado
create or replace function plone27_trg_tasas_pasarela() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare t record; orig uuid; ben uuid; tx uuid; begin
  for t in select x.tasa, x.pagador, x.beneficiario, x.importe from plone27_tasas_aplicables(new.bank_id,new.client_id,new.medio,new.importe) x loop
    if t.importe<=0 then continue; end if;
    orig:=case when t.pagador='comercio' then new.cuenta_destino else plone27_comision_cuenta(new.bank_id) end;
    ben:=case when t.beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(new.bank_id) end;
    if orig=ben then continue; end if;
    tx:=plone27_transfer('tasa:'||new.id::text||':'||t.tasa::text,orig,ben,t.importe,'Tasa de pasarela',null);
    insert into plone27_tasas_cobradas(checkout,tasa,importe,pagador,beneficiario,tx)
      values(new.id,t.tasa,t.importe,t.pagador,t.beneficiario,tx) on conflict(checkout,tasa) do nothing;
  end loop;
  return new; end $$;
drop trigger if exists trg_tasas_pasarela on plone27_checkouts;
drop trigger if exists trg_tasas_pasarela on plone27_checkouts;
create trigger trg_tasas_pasarela after update of estado on plone27_checkouts
  for each row when (new.estado='pagado' and old.estado is distinct from 'pagado')
  execute function plone27_trg_tasas_pasarela();

-- ---------- Alta y baja de tasas ----------
-- La administración (ámbito propietario) puede fijar cualquier tasa; el banco solo las suyas, que cobra él a sus comercios.
create or replace function plone27_tasa_alta(p_bank uuid,p_ambito text,p_client uuid,p_medio text,p_tipo text,p_valor numeric,
    p_minimo numeric,p_maximo numeric,p_pagador text,p_beneficiario text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare tid uuid; begin
  if not exists(select 1 from plone27_banks b where b.id=p_bank and b.active) then raise exception 'Entidad no encontrada'; end if;
  if p_client is not null and not exists(select 1 from plone27_api_clients c where c.id=p_client and c.bank_id=p_bank) then
    raise exception 'El cliente no pertenece a la entidad';
  end if;
  if p_ambito='banco' and (p_pagador<>'comercio' or p_beneficiario<>'banco') then
    raise exception 'La entidad solo puede cobrar tasas a sus comercios para su propio beneficio';
  end if;
  insert into plone27_tasas(ambito,bank_id,client_id,medio,tipo,valor,minimo,maximo,pagador,beneficiario)
    values(p_ambito,p_bank,p_client,p_medio,p_tipo,p_valor,coalesce(p_minimo,0),p_maximo,p_pagador,p_beneficiario)
    returning plone27_tasas.id into tid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tasa_alta','bank',p_bank::text,jsonb_build_object('tasa',tid,'ambito',p_ambito,'valor',p_valor,'tipo',p_tipo));
  return tid; end $$;

create or replace function plone27_tasa_desactivar(p_bank uuid,p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_tasas set activa=false where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Tasa no encontrada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tasa_desactivar','bank',p_bank::text,jsonb_build_object('tasa',p_id));
end $$;

create or replace function plone27_tasas_listar(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select t.id, t.ambito, t.client_id, t.medio, t.tipo, t.valor, t.minimo, t.maximo, t.pagador, t.beneficiario, t.activa, t.creada
    from plone27_tasas t where t.bank_id=p_bank) x $$;

-- ---------- Operaciones interbancarias de la entidad ----------
create or replace function plone27_interbancarias(p_bank uuid,p_desde date,p_hasta date) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select c.id, c.client_ref as referencia, c.estado, c.importe, c.comision, c.comision_pagador, c.creada,
      case when c.banco_pagador=p_bank then 'pagada' else 'cobrada' end as sentido,
      (select b.code from plone27_accounts a join plone27_banks b on b.id=a.bank_id where a.id=c.cuenta_destino) as banco_destino
    from plone27_checkouts c
    where c.interbancaria and (c.banco_pagador=p_bank or c.bank_id=p_bank)
      and c.creada::date between p_desde and p_hasta) x $$;

-- Posición neta de la entidad frente a cada banco con operaciones pagadas en el periodo
create or replace function plone27_posicion_interbancaria(p_bank uuid,p_desde date,p_hasta date) returns jsonb
language sql stable security definer set search_path=public as $$
  with ops as(
    select c.banco_pagador as origen, a.bank_id as destino, c.importe
    from plone27_checkouts c join plone27_accounts a on a.id=c.cuenta_destino
    where c.estado='pagado' and c.interbancaria and c.resuelta::date between p_desde and p_hasta),
  contra as(
    select distinct case when o.origen=p_bank then o.destino else o.origen end as banco
    from ops o where p_bank in(o.origen,o.destino) and o.origen<>o.destino)
  select coalesce(jsonb_agg(to_jsonb(x) order by x.banco_codigo),'[]'::jsonb) from (
    select b.code as banco_codigo, b.name as banco,
      coalesce((select sum(o.importe) from ops o where o.origen=p_bank and o.destino=ct.banco),0) as enviado,
      coalesce((select sum(o.importe) from ops o where o.origen=ct.banco and o.destino=p_bank),0) as recibido,
      coalesce((select sum(o.importe) from ops o where o.origen=ct.banco and o.destino=p_bank),0)
        -coalesce((select sum(o.importe) from ops o where o.origen=p_bank and o.destino=ct.banco),0) as neto
    from contra ct join plone27_banks b on b.id=ct.banco) x $$;

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

-- ==================== MIGRACIÓN (0038_plone27_admin_cifrado_rotacion.sql) ====================
-- Placeta One · 0038 · Cifrado de secretos de webhook, rotación de la clave de la pasarela de una empresa
-- y suspensión de empresas. Requiere 0037. Idempotente.

-- Marca de los secretos cifrados (los antiguos, en claro, se cifran al rotarlos)
alter table plone27_webhooks add column if not exists cifrado boolean generated always as (secret like 'enc:v1:%') stored;

-- Rotación de la clave de la pasarela de una empresa (solo un titular activo)
create or replace function plone27_empresa_pasarela_rotar(p_bank uuid,p_empresa uuid,p_key_hash text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  if not exists(select 1 from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank and e.estado='activa') then
    raise exception 'Empresa no encontrada o no activa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede rotar su clave';
  end if;
  select pe.client_id into cid from plone27_empresa_pasarelas pe where pe.empresa_id=p_empresa and pe.activa;
  if cid is null then raise exception 'La empresa no tiene pasarela activa'; end if;
  update plone27_api_clients set key_hash=p_key_hash where id=cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_clave_rotada','empresa',p_empresa::text,jsonb_build_object('client',cid));
  return cid; end $$;

-- Estado de la empresa. Suspender o dar de baja desactiva su pasarela; volver a activar la restaura.
create or replace function plone27_empresa_estado(p_bank uuid,p_empresa uuid,p_estado text,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  if p_estado not in('activa','suspendida','baja') then raise exception 'Estado no válido'; end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null)
     and p_actor is not null then
    raise exception 'Solo un titular de la empresa puede cambiar su estado';
  end if;
  with x as(update plone27_empresas set estado=p_estado where id=p_empresa and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Empresa no encontrada'; end if;
  update plone27_empresa_pasarelas pe set activa=(p_estado='activa') where pe.empresa_id=p_empresa;
  update plone27_api_clients c set active=(p_estado='activa')
    where c.id in(select pe.client_id from plone27_empresa_pasarelas pe where pe.empresa_id=p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_estado','empresa',p_empresa::text,jsonb_build_object('estado',p_estado,'motivo',p_motivo));
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

-- ==================== MIGRACIÓN (0039_plone27_webhooks_rotacion_forzada.sql) ====================
-- Placeta One · 0039 · Rotación forzada de secretos de webhook sin cifrar.
-- Desactiva los webhooks con secreto en claro; al rotarlos, el banco vuelve a quedar activo con secreto cifrado.
-- Requiere 0038. Idempotente.

create or replace function plone27_bk_webhook_rotar(p_bank uuid,p_id uuid,p_secret text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_webhooks set secret=p_secret, active=true where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Webhook no encontrado'; end if;
end $$;

create or replace function plone27_webhooks_desactivar_sin_cifrar(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_webhooks set active=false where active and secret not like 'enc:v1:%' returning 1)
  select count(*) into n from x;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'webhooks_desactivados_sin_cifrar','webhook',null,jsonb_build_object('n',n));
  return n; end $$;

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

-- ==================== MIGRACIÓN (0040_plone27_liquidacion_tasas_reversion.sql) ====================
-- Placeta One · 0040 · Liquidación interbancaria neta diaria, límite de exposición, reversión con doble aprobación
-- y motor de tasas para transferencias interbancarias y cargos de tarjeta de empresa.
-- Todo empieza DESACTIVADO (plone27_config_interbancaria). Requiere 0039. Idempotente.

-- ---------- Interruptores ----------
create table if not exists plone27_config_interbancaria(
  id int primary key default 1 check(id=1),
  liquidacion_activa boolean not null default false,
  tasas_operaciones_activas boolean not null default false,
  actualizada timestamptz not null default now());
insert into plone27_config_interbancaria(id) values(1) on conflict(id) do nothing;

-- ---------- Liquidaciones, operaciones pendientes de liquidar y límites ----------
create table if not exists plone27_liquidaciones(
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  banco_deudor uuid not null references plone27_banks,
  banco_acreedor uuid not null references plone27_banks,
  importe numeric(18,2) not null check(importe>0),
  estado text not null check(estado in('pendiente','ejecutada','revertida','compensatoria')),
  motivo text check(motivo is null or length(motivo)>=10),
  revierte uuid references plone27_liquidaciones(id),
  tx uuid,
  aprobada_por uuid,
  aprobada_por2 uuid,
  creada timestamptz not null default now(),
  check(banco_deudor<>banco_acreedor));

create table if not exists plone27_operaciones_interbancarias(
  id bigint generated always as identity primary key,
  origen uuid not null references plone27_banks,
  destino uuid not null references plone27_banks,
  importe numeric(18,2) not null check(importe>0),
  ref text not null unique,
  fecha date not null default current_date,
  liquidada_en uuid references plone27_liquidaciones(id),
  check(origen<>destino));

create table if not exists plone27_limites_exposicion(
  bank_deudor uuid not null references plone27_banks,
  bank_acreedor uuid not null references plone27_banks,
  limite numeric(18,2) not null check(limite>=0),
  primary key(bank_deudor,bank_acreedor),
  check(bank_deudor<>bank_acreedor));

create table if not exists plone27_reversiones(
  id uuid primary key default gen_random_uuid(),
  liquidacion uuid not null references plone27_liquidaciones(id),
  motivo text not null check(length(motivo)>=10),
  solicitada_por uuid not null,
  aprobada_por uuid,
  estado text not null default 'pendiente' check(estado in('pendiente','ejecutada','rechazada')),
  creada timestamptz not null default now(),
  resuelta timestamptz);
create unique index if not exists plone27_reversion_pendiente_ux on plone27_reversiones(liquidacion) where estado='pendiente';

-- ---------- Tasas: nuevas operaciones (la tasa la paga siempre el banco emisor) ----------
alter table plone27_tasas drop constraint if exists plone27_tasas_operacion_check;
do $$ begin alter table plone27_tasas add constraint plone27_tasas_operacion_check
  check(operacion in('pasarela_pago','transferencia_interbancaria','cargo_tarjeta_empresa')) not valid; exception when duplicate_object then null; end $$;

create or replace function plone27_tasas_operacion(p_bank uuid,p_operacion text,p_medio text,p_importe numeric)
returns table(tasa uuid,beneficiario text,monto numeric)
language sql stable security definer set search_path=public as $$
  select t.id, t.beneficiario,
    round(least(greatest(case when t.tipo='fijo' then t.valor else p_importe*t.valor/100 end, t.minimo),
      coalesce(t.maximo,999999999999)),2)
  from plone27_tasas t
  where t.activa and t.bank_id=p_bank and t.operacion=p_operacion and t.client_id is null
    and (t.medio is null or t.medio=p_medio) $$;

create or replace function plone27_tasa_alta_operacion(p_bank uuid,p_operacion text,p_tipo text,p_valor numeric,p_minimo numeric,p_maximo numeric,
    p_beneficiario text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare tid uuid; begin
  if p_operacion not in('transferencia_interbancaria','cargo_tarjeta_empresa') then raise exception 'Operación no válida'; end if;
  if not exists(select 1 from plone27_banks b where b.id=p_bank) then raise exception 'Entidad no encontrada'; end if;
  insert into plone27_tasas(ambito,bank_id,operacion,tipo,valor,minimo,maximo,pagador,beneficiario)
    values('propietario',p_bank,p_operacion,p_tipo,p_valor,coalesce(p_minimo,0),p_maximo,'banco',p_beneficiario)
    returning plone27_tasas.id into tid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tasa_operacion_alta','bank',p_bank::text,jsonb_build_object('operacion',p_operacion,'valor',p_valor,'tipo',p_tipo));
  return tid; end $$;

-- Cobra las tasas de una operación interbancaria. Misma entidad: exenta. Cargos de tarjeta: solo cuentas de empresa.
-- Con el interruptor apagado no hace nada y devuelve 0.
create or replace function plone27_cobrar_tasa(p_operacion text,p_cuenta_origen uuid,p_cuenta_destino uuid,p_importe numeric,p_key text,p_actor uuid)
returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ob uuid; db uuid; okind text; t record; total numeric:=0; orig uuid; ben uuid; begin
  if not coalesce((select c.tasas_operaciones_activas from plone27_config_interbancaria c where c.id=1),false) then return 0; end if;
  select a.bank_id, a.kind into ob, okind from plone27_accounts a where a.id=p_cuenta_origen;
  select a.bank_id into db from plone27_accounts a where a.id=p_cuenta_destino;
  if ob is null or db is null or ob=db then return 0; end if;
  if p_operacion='cargo_tarjeta_empresa' and okind<>'business' then return 0; end if;
  for t in select x.tasa, x.beneficiario, x.monto from plone27_tasas_operacion(ob,p_operacion,null,p_importe) x loop
    if t.monto<=0 then continue; end if;
    orig:=plone27_comision_cuenta(ob);
    ben:=case when t.beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(ob) end;
    if orig=ben then continue; end if;
    perform plone27_transfer('tasa-op:'||p_key||':'||t.tasa::text,orig,ben,t.monto,'Tasa interbancaria',p_actor);
    total:=total+t.monto;
  end loop;
  return total; end $$;

-- ---------- Registro de operaciones interbancarias pagadas ----------
create or replace function plone27_registrar_op(p_origen uuid,p_destino uuid,p_importe numeric,p_ref text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_origen is null or p_destino is null or p_origen=p_destino then return; end if;
  insert into plone27_operaciones_interbancarias(origen,destino,importe,ref) values(p_origen,p_destino,p_importe,p_ref)
    on conflict(ref) do nothing;
end $$;

create or replace function plone27_trg_ops_checkout() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare dest uuid; begin
  if not new.interbancaria then return new; end if;
  select a.bank_id into dest from plone27_accounts a where a.id=new.cuenta_destino;
  perform plone27_registrar_op(new.banco_pagador,dest,new.importe,'checkout:'||new.id::text);
  return new; end $$;
drop trigger if exists trg_ops_checkout on plone27_checkouts;
drop trigger if exists trg_ops_checkout on plone27_checkouts;
create trigger trg_ops_checkout after update of estado on plone27_checkouts
  for each row when (new.estado='pagado' and old.estado is distinct from 'pagado')
  execute function plone27_trg_ops_checkout();

-- ---------- Límite de exposición: se comprueba antes de crear un pago interbancario ----------
create or replace function plone27_trg_limite_exposicion() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare dest uuid; lim numeric; neto numeric; begin
  if not new.interbancaria then return new; end if;
  select a.bank_id into dest from plone27_accounts a where a.id=new.cuenta_destino;
  select l.limite into lim from plone27_limites_exposicion l where l.bank_deudor=new.banco_pagador and l.bank_acreedor=dest;
  if lim is null then return new; end if;
  select coalesce(sum(case when o.origen=new.banco_pagador then o.importe else -o.importe end),0) into neto
    from plone27_operaciones_interbancarias o
    where o.liquidada_en is null and ((o.origen=new.banco_pagador and o.destino=dest) or (o.origen=dest and o.destino=new.banco_pagador));
  neto:=neto+coalesce((select sum(c.importe) from plone27_checkouts c join plone27_accounts a on a.id=c.cuenta_destino
    where c.estado='pendiente' and c.interbancaria and c.banco_pagador=new.banco_pagador and a.bank_id=dest and c.expira_at>now()),0);
  if neto+new.importe>lim then
    raise exception 'Tu entidad ha alcanzado su límite de exposición con ese banco: hay que liquidar antes de nuevos pagos interbancarios';
  end if;
  return new; end $$;
drop trigger if exists trg_limite_exposicion on plone27_checkouts;
drop trigger if exists trg_limite_exposicion on plone27_checkouts;
create trigger trg_limite_exposicion before insert on plone27_checkouts
  for each row execute function plone27_trg_limite_exposicion();

-- ---------- Cuenta de liquidación de cada banco (la financia el propio banco) ----------
create or replace function plone27_cuenta_liquidacion(p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  select a.id into cid from plone27_accounts a where a.bank_id=p_bank and a.kind='system' and a.name='Liquidación interbancaria' limit 1;
  if cid is null then cid:=(plone27_open_account(p_bank,'system','Liquidación interbancaria',null,null)->>'id')::uuid; end if;
  return cid; end $$;

create or replace function plone27_limite_set(p_deudor uuid,p_acreedor uuid,p_limite numeric,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_deudor=p_acreedor then raise exception 'Un banco no tiene límite frente a sí mismo'; end if;
  insert into plone27_limites_exposicion(bank_deudor,bank_acreedor,limite) values(p_deudor,p_acreedor,p_limite)
    on conflict(bank_deudor,bank_acreedor) do update set limite=excluded.limite;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'limite_exposicion','bank',p_deudor::text,jsonb_build_object('acreedor',p_acreedor,'limite',p_limite));
end $$;

-- ---------- Liquidación neta: todo o nada ----------
create or replace function plone27_liquidar(p_fecha date,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v_liq boolean; r record; v_a uuid; v_b uuid; v_neto numeric; v_deudor uuid; v_acreedor uuid; v_monto numeric;
  v_ca uuid; v_cb uuid; v_id uuid; v_tx uuid; v_n int:=0; v_code text; begin
  perform pg_advisory_xact_lock(hashtext('plone27_liquidacion'));
  select c.liquidacion_activa into v_liq from plone27_config_interbancaria c where c.id=1;
  if not coalesce(v_liq,false) then raise exception 'La liquidación interbancaria está desactivada'; end if;
  for r in select distinct least(o.origen,o.destino) as ba, greatest(o.origen,o.destino) as bb
           from plone27_operaciones_interbancarias o where o.liquidada_en is null and o.fecha<=p_fecha loop
    v_a:=r.ba; v_b:=r.bb;
    select coalesce(sum(case when o.origen=v_a then o.importe else -o.importe end),0) into v_neto
      from plone27_operaciones_interbancarias o
      where o.liquidada_en is null and o.fecha<=p_fecha and ((o.origen=v_a and o.destino=v_b) or (o.origen=v_b and o.destino=v_a));
    if v_neto=0 then continue; end if;
    if v_neto>0 then v_deudor:=v_a; v_acreedor:=v_b; else v_deudor:=v_b; v_acreedor:=v_a; end if;
    v_monto:=abs(v_neto);
    v_ca:=plone27_cuenta_liquidacion(v_deudor); v_cb:=plone27_cuenta_liquidacion(v_acreedor);
    if plone27_available(v_ca)<v_monto then
      select b.code into v_code from plone27_banks b where b.id=v_deudor;
      raise exception 'El banco % no tiene saldo en su cuenta de liquidación para pagar % Pz', v_code, v_monto;
    end if;
    insert into plone27_liquidaciones(fecha,banco_deudor,banco_acreedor,importe,estado)
      values(p_fecha,v_deudor,v_acreedor,v_monto,'pendiente') returning plone27_liquidaciones.id into v_id;
    v_tx:=plone27_transfer('liq:'||v_id::text,v_ca,v_cb,v_monto,'Liquidación interbancaria',p_actor);
    update plone27_liquidaciones set estado='ejecutada', tx=v_tx where id=v_id;
    update plone27_operaciones_interbancarias o set liquidada_en=v_id
      where o.liquidada_en is null and o.fecha<=p_fecha and ((o.origen=v_a and o.destino=v_b) or (o.origen=v_b and o.destino=v_a));
    v_n:=v_n+1;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'liquidacion_ejecutada','liquidacion',null,jsonb_build_object('fecha',p_fecha,'n',v_n));
  return jsonb_build_object('fecha',p_fecha,'liquidaciones',v_n); end $$;

-- ---------- Reversión: compensatoria, con dos personas distintas; reabre las operaciones para volver a liquidarlas ----------
create or replace function plone27_revertir_liquidacion(p_liq uuid,p_motivo text,p_solicitante uuid,p_aprobador uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare o plone27_liquidaciones; v_id uuid; v_ca uuid; v_cb uuid; v_tx uuid; begin
  if p_solicitante is null or p_aprobador is null or p_solicitante=p_aprobador then raise exception 'La reversión necesita dos personas distintas'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'El motivo debe tener al menos 10 caracteres'; end if;
  select * into o from plone27_liquidaciones where id=p_liq for update;
  if o.id is null or o.estado<>'ejecutada' then raise exception 'Solo se revierten liquidaciones ejecutadas'; end if;
  insert into plone27_liquidaciones(fecha,banco_deudor,banco_acreedor,importe,estado,motivo,revierte,aprobada_por,aprobada_por2)
    values(current_date,o.banco_acreedor,o.banco_deudor,o.importe,'compensatoria',p_motivo,o.id,p_solicitante,p_aprobador)
    returning plone27_liquidaciones.id into v_id;
  v_ca:=plone27_cuenta_liquidacion(o.banco_acreedor); v_cb:=plone27_cuenta_liquidacion(o.banco_deudor);
  if plone27_available(v_ca)<o.importe then raise exception 'La entidad acreedora no tiene saldo para devolver la liquidación'; end if;
  v_tx:=plone27_transfer('rev:'||v_id::text,v_ca,v_cb,o.importe,'Reversión de liquidación',p_aprobador);
  update plone27_liquidaciones set estado='ejecutada', tx=v_tx where id=v_id;
  update plone27_liquidaciones set estado='revertida' where id=o.id;
  update plone27_operaciones_interbancarias set liquidada_en=null where liquidada_en=o.id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_aprobador,'liquidacion_revertida','liquidacion',o.id::text,jsonb_build_object('compensatoria',v_id,'motivo',p_motivo));
  return v_id; end $$;

create or replace function plone27_reversion_solicitar(p_liq uuid,p_motivo text,p_solicitante uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rid uuid; begin
  if not exists(select 1 from plone27_liquidaciones l where l.id=p_liq and l.estado='ejecutada') then
    raise exception 'Solo se puede pedir la reversión de una liquidación ejecutada';
  end if;
  insert into plone27_reversiones(liquidacion,motivo,solicitada_por) values(p_liq,p_motivo,p_solicitante)
    returning plone27_reversiones.id into rid;
  return rid; end $$;

create or replace function plone27_reversion_aprobar(p_id uuid,p_aprobador uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rv plone27_reversiones; v uuid; begin
  select * into rv from plone27_reversiones r where r.id=p_id and r.estado='pendiente' for update;
  if rv.id is null then raise exception 'Solicitud de reversión no encontrada o ya resuelta'; end if;
  if rv.solicitada_por=p_aprobador then raise exception 'Quien solicita la reversión no puede aprobarla'; end if;
  v:=plone27_revertir_liquidacion(rv.liquidacion,rv.motivo,rv.solicitada_por,p_aprobador);
  update plone27_reversiones set estado='ejecutada', aprobada_por=p_aprobador, resuelta=now() where id=p_id;
  return v; end $$;

-- ---------- Interruptores ----------
create or replace function plone27_config_interbancaria_set(p_liquidacion boolean,p_tasas boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  update plone27_config_interbancaria set liquidacion_activa=coalesce(p_liquidacion,false),
    tasas_operaciones_activas=coalesce(p_tasas,false), actualizada=now() where id=1;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'config_interbancaria','config',null,jsonb_build_object('liquidacion',p_liquidacion,'tasas',p_tasas));
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

-- ==================== MIGRACIÓN (0041_plone27_conexion_liquidacion_tasas.sql) ====================
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

-- ==================== MIGRACIÓN (0042_plone27_disputas_deudas_usuario_logos.sql) ====================
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

-- ==================== MIGRACIÓN (0043_plone27_idempotencia_parametros_disputas.sql) ====================
-- Placeta One · 0043 · Corrección de idempotencia en el cobro de deudas, parámetros configurables de disputas.
-- Requiere 0042. Idempotente. NO ejecutado en PostgreSQL: probar con verificacion/pruebas_db.sql antes de producción.

-- ---------- Parámetros configurables (plazos y umbrales) ----------
create table if not exists plone27_parametros(
  clave text primary key,
  valor numeric(18,4) not null,
  actualizado timestamptz not null default now(),
  actor uuid);
insert into plone27_parametros(clave,valor) values
  ('disputa.plazo_apertura_dias',60),
  ('disputa.plazo_resolucion_dias',30),
  ('disputa.umbral_doble_aprobacion',1000)
on conflict(clave) do nothing;

create or replace function plone27_parametro(p_clave text) returns numeric
language sql stable security definer set search_path=public as $$
  select valor from plone27_parametros where clave=p_clave $$;

create or replace function plone27_parametro_set(p_clave text,p_valor numeric,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_clave not in('disputa.plazo_apertura_dias','disputa.plazo_resolucion_dias','disputa.umbral_doble_aprobacion') then
    raise exception 'Parámetro no válido';
  end if;
  if p_clave='disputa.plazo_apertura_dias' and (p_valor<1 or p_valor>365) then raise exception 'Plazo de apertura entre 1 y 365 días'; end if;
  if p_clave='disputa.plazo_resolucion_dias' and (p_valor<1 or p_valor>180) then raise exception 'Plazo de resolución entre 1 y 180 días'; end if;
  if p_clave='disputa.umbral_doble_aprobacion' and (p_valor<0 or p_valor>1000000) then raise exception 'Umbral entre 0 y 1.000.000 Pz'; end if;
  insert into plone27_parametros(clave,valor,actor) values(p_clave,p_valor,p_actor)
    on conflict(clave) do update set valor=excluded.valor, actualizado=now(), actor=excluded.actor;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'parametro_set','parametro',p_clave,jsonb_build_object('valor',p_valor));
end $$;

-- ---------- Cobro de deuda: IDEMPOTENTE ----------
-- Una clave repetida con los mismos datos devuelve la transacción original y NO vuelve a sumar el pago a la deuda.
-- Una clave repetida con datos distintos falla.
create or replace function plone27_debt_pay(p_key text,p_debt uuid,p_amount numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; tx uuid; ob uuid; db uuid; h text; viejo text; begin
  select * into d from plone27_debts where id=p_debt for update;
  if d.id is null then raise exception 'Deuda no encontrada'; end if;
  if d.creditor_account is null then raise exception 'La deuda no tiene acreedor'; end if;
  -- misma huella que calcula plone27_post para la transferencia equivalente
  h:=md5('transfer'||jsonb_build_array(
      jsonb_build_object('account',d.account_id,'dir','debit','amount',p_amount),
      jsonb_build_object('account',d.creditor_account,'dir','credit','amount',p_amount))::text);
  select t.id, t.req_hash into tx, viejo from plone27_transactions t where t.idempotency_key=p_key;
  if tx is not null then
    if viejo is not null and viejo<>h then raise exception 'Idempotency-Key reutilizada con datos distintos'; end if;
    return tx;
  end if;
  if d.disputed then raise exception 'Deuda en disputa: no se cobra'; end if;
  if d.paid+p_amount>d.principal+d.authorized_charges then raise exception 'Excede la deuda'; end if;
  tx:=plone27_transfer(p_key,d.account_id,d.creditor_account,p_amount,'Deuda '||d.ref,p_actor);
  update plone27_debts set paid=paid+p_amount where id=p_debt;
  select a.bank_id into ob from plone27_accounts a where a.id=d.account_id;
  select a.bank_id into db from plone27_accounts a where a.id=d.creditor_account;
  if ob is not null and db is not null and ob<>db then perform plone27_registrar_op(ob,db,p_amount,'deuda:'||tx::text); end if;
  return tx;
end $$;

-- ---------- Reclamación con plazos desde parámetros ----------
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
  if current_date>coalesce(d.due_date,current_date)+plone27_parametro('disputa.plazo_apertura_dias')::int then
    raise exception 'El plazo para reclamar ha vencido';
  end if;
  if exists(select 1 from plone27_disputas x where x.debt_id=p_debt and x.estado='abierta') then
    raise exception 'Ya hay una reclamación abierta para esta deuda';
  end if;
  insert into plone27_disputas(debt_id,account_id,monto_reclamado,motivo,abierta_por,plazo_resolucion)
    values(p_debt,d.account_id,p_monto,p_motivo,p_user,current_date+plone27_parametro('disputa.plazo_resolucion_dias')::int)
    returning plone27_disputas.id into did;
  update plone27_debts set disputed=true where id=p_debt;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_user,'disputa_abierta','deuda',p_debt::text,jsonb_build_object('monto',p_monto));
  return did; end $$;

-- ---------- Resolución con umbral desde parámetros ----------
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
  if m>plone27_parametro('disputa.umbral_doble_aprobacion') then
    if x.aprobada_1 is null then
      update plone27_disputas set aprobada_1=p_actor where id=p_id;
      return jsonb_build_object('estado','pendiente_segunda_aprobacion');
    end if;
    if x.aprobada_1=p_actor then raise exception 'Otra persona debe aprobar esta devolución'; end if;
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

-- ==================== MIGRACIÓN (0044_plone27_reglas_uso_categorias_subvenciones.sql) ====================
-- Placeta One · 0044 · Reglas de uso de RBU y de subvenciones (tipos de cuenta, comercios y categorías),
-- categorías de comercio (Placeta), y API de programas, concesiones, justificaciones y reglas para bancos.
-- Requiere 0043. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- ---------- Categorías de comercio (las asigna Placeta) ----------
create table if not exists plone27_categorias(
  codigo text primary key check(codigo ~ '^[a-z_]{3,30}$'),
  nombre text not null check(length(nombre) between 3 and 60),
  activa boolean not null default true);
insert into plone27_categorias(codigo,nombre) values
  ('alimentacion','Alimentación'),('salud','Salud'),('educacion','Educación'),('transporte','Transporte'),
  ('vivienda','Vivienda'),('ocio','Ocio'),('otros','Otros')
on conflict(codigo) do nothing;

alter table plone27_accounts add column if not exists categoria text references plone27_categorias(codigo);
alter table plone27_accounts drop constraint if exists plone27_accounts_categoria_business;
do $$ begin alter table plone27_accounts add constraint plone27_accounts_categoria_business check(categoria is null or kind='business') not valid; exception when duplicate_object then null; end $$;

-- ---------- Reglas de destino (RBU por bono, o por programa de subvención) ----------
create table if not exists plone27_politicas_destino(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks,
  ambito text not null check(ambito in('rbu','programa')),
  programa_id uuid references plone27_grant_programs,
  tipos_destino text[] not null default '{}',
  comercios uuid[] not null default '{}',
  categorias text[] not null default '{}',
  activa boolean not null default true,
  creada timestamptz not null default now(),
  check((ambito='programa' and programa_id is not null) or (ambito='rbu' and programa_id is null)),
  check(tipos_destino <@ array['personal','business','shared','junior','system']::text[]));
create unique index if not exists plone27_politica_rbu_ux on plone27_politicas_destino(bank_id) where ambito='rbu' and activa;
create unique index if not exists plone27_politica_programa_ux on plone27_politicas_destino(programa_id) where ambito='programa' and activa;

-- ¿Puede esta regla pagar a esta cuenta? Cada filtro configurado debe cumplirse. Un filtro vacío no restringe.
create or replace function plone27_destino_permitido(p_politica uuid,p_destino uuid) returns boolean
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare p plone27_politicas_destino; c plone27_accounts; begin
  select * into p from plone27_politicas_destino where id=p_politica;
  select * into c from plone27_accounts where id=p_destino;
  if p.id is null or c.id is null then return false; end if;
  if cardinality(p.tipos_destino)>0 and not(c.kind=any(p.tipos_destino)) then return false; end if;
  if cardinality(p.comercios)>0 and not(c.id=any(p.comercios)) then return false; end if;
  if cardinality(p.categorias)>0 and not(coalesce(c.categoria,'')=any(p.categorias)) then return false; end if;
  return true; end $$;

-- RBU: cada cargo de tarjeta prepago se comprueba contra la regla RBU del banco de la tarjeta
create or replace function plone27_trg_rbu_destino() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; bk uuid; pol uuid; begin
  select cd.* into c from plone27_cards cd where cd.id=new.card_id;
  if c.id is null or c.kind<>'prepago' then return new; end if;
  select a.bank_id into bk from plone27_accounts a where a.id=c.account_id;
  select p.id into pol from plone27_politicas_destino p where p.bank_id=bk and p.ambito='rbu' and p.activa;
  if pol is null then return new; end if;
  if not plone27_destino_permitido(pol,new.merchant_account) then
    raise exception 'Esta tarjeta RBU no puede pagar en ese comercio';
  end if;
  return new; end $$;
drop trigger if exists trg_rbu_destino on plone27_card_charges;
drop trigger if exists trg_rbu_destino on plone27_card_charges;
create trigger trg_rbu_destino before insert on plone27_card_charges
  for each row execute function plone27_trg_rbu_destino();

-- Subvención: la justificación debe ser un gasto de la cuenta beneficiaria cuyo destino cumple la regla del programa
create or replace function plone27_trg_justificacion_destino() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; pol uuid; dest uuid; begin
  select * into g from plone27_grants where id=new.grant_id;
  select p.id into pol from plone27_politicas_destino p where p.programa_id=g.program_id and p.activa;
  if pol is null then return new; end if;
  if not exists(select 1 from plone27_ledger_entries l where l.transaction_id=new.transaction_id
                and l.account_id=g.beneficiary_account and l.direction='debit') then
    raise exception 'La transacción no es un gasto de la cuenta beneficiaria';
  end if;
  select l.account_id into dest from plone27_ledger_entries l
    where l.transaction_id=new.transaction_id and l.direction='credit' and l.account_id<>g.beneficiary_account limit 1;
  if dest is null then raise exception 'La transacción no tiene un destino que justificar'; end if;
  if not plone27_destino_permitido(pol,dest) then
    raise exception 'El destino de ese gasto no está permitido por la convocatoria';
  end if;
  return new; end $$;
drop trigger if exists trg_justificacion_destino on plone27_justifications;
drop trigger if exists trg_justificacion_destino on plone27_justifications;
create trigger trg_justificacion_destino before insert on plone27_justifications
  for each row execute function plone27_trg_justificacion_destino();

-- ---------- Administración de Placeta: categorías y categoría de cada comercio ----------
create or replace function plone27_categoria_set(p_codigo text,p_nombre text,p_activa boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_codigo is null or p_codigo !~ '^[a-z_]{3,30}$' then raise exception 'Código de categoría no válido'; end if;
  insert into plone27_categorias(codigo,nombre,activa) values(p_codigo,p_nombre,coalesce(p_activa,true))
    on conflict(codigo) do update set nombre=excluded.nombre, activa=excluded.activa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'categoria_set','categoria',p_codigo,jsonb_build_object('activa',p_activa));
end $$;

create or replace function plone27_cuenta_categoria_set(p_iban text,p_categoria text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  if p_categoria is not null and not exists(select 1 from plone27_categorias c where c.codigo=p_categoria and c.activa) then
    raise exception 'Categoría no válida';
  end if;
  with x as(update plone27_accounts set categoria=p_categoria where iban=p_iban and kind='business' returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Solo se pueden categorizar cuentas de comercio (empresa)'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'comercio_categoria','cuenta',p_iban,jsonb_build_object('categoria',p_categoria));
end $$;

-- ---------- API de banco: catálogos ----------
create or replace function plone27_bk_categorias() returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.codigo),'[]'::jsonb) from (
    select c.codigo, c.nombre from plone27_categorias c where c.activa) x $$;

-- Directorio de comercios: cuentas de empresa activas, sin saldos
create or replace function plone27_bk_comercios() returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.nombre),'[]'::jsonb) from (
    select a.iban, a.name as nombre, a.categoria, b.code as banco
    from plone27_accounts a join plone27_banks b on b.id=a.bank_id
    where a.kind='business' and a.status='active') x $$;

-- ---------- API de banco: programas, concesiones y justificaciones ----------
create or replace function plone27_bk_programas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.nombre),'[]'::jsonb) from (
    select gp.id, gp.name as nombre, gp.kind as tipo, gp.budget as presupuesto, a.iban as cuenta_fondos,
      (select count(*) from plone27_grants g where g.program_id=gp.id) as concesiones
    from plone27_grant_programs gp join plone27_accounts a on a.id=gp.funding_account
    where a.bank_id=p_bank) x $$;

create or replace function plone27_bk_programa_crear(p_bank uuid,p_name text,p_kind text,p_budget numeric,p_funding_iban text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; pid uuid; begin
  if p_kind not in('subvencion','bono') then raise exception 'Tipo no válido (subvencion o bono)'; end if;
  if coalesce(length(p_name),0)<3 then raise exception 'Nombre demasiado corto'; end if;
  if p_budget is null or p_budget<=0 then raise exception 'Presupuesto no válido'; end if;
  select a.id into f from plone27_accounts a where a.iban=p_funding_iban and a.bank_id=p_bank;
  if f is null then raise exception 'La cuenta de fondos debe ser de tu entidad'; end if;
  insert into plone27_grant_programs(name,kind,budget,funding_account) values(p_name,p_kind,p_budget,f)
    returning plone27_grant_programs.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'programa_crear','programa',pid::text,jsonb_build_object('tipo',p_kind,'presupuesto',p_budget));
  return pid; end $$;

create or replace function plone27_bk_concesiones(p_bank uuid,p_program uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.programa, x.beneficiario),'[]'::jsonb) from (
    select g.id, g.program_id, gp.name as programa, b.iban as beneficiario,
      g.granted as concedido, g.approved as aprobado, g.paid as pagado
    from plone27_grants g join plone27_grant_programs gp on gp.id=g.program_id
    join plone27_accounts fa on fa.id=gp.funding_account
    join plone27_accounts b on b.id=g.beneficiary_account
    where fa.bank_id=p_bank and (p_program is null or g.program_id=p_program)) x $$;

create or replace function plone27_bk_concesion_crear(p_bank uuid,p_program uuid,p_beneficiary_iban text,p_granted numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b uuid; gid uuid; begin
  if not exists(select 1 from plone27_grant_programs gp join plone27_accounts fa on fa.id=gp.funding_account
                where gp.id=p_program and fa.bank_id=p_bank) then raise exception 'Programa no encontrado en tu entidad'; end if;
  select a.id into b from plone27_accounts a where a.iban=p_beneficiary_iban and a.bank_id=p_bank and a.status='active';
  if b is null then raise exception 'El beneficiario debe ser una cuenta activa de tu entidad'; end if;
  if p_granted is null or p_granted<=0 then raise exception 'Importe concedido no válido'; end if;
  insert into plone27_grants(program_id,beneficiary_account,granted) values(p_program,b,p_granted)
    returning plone27_grants.id into gid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'concesion_crear','concesion',gid::text,jsonb_build_object('concedido',p_granted));
  return gid; end $$;

create or replace function plone27_bk_justificaciones(p_bank uuid,p_grant uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) from (
    select j.id, j.grant_id, j.transaction_id, j.invoice_ref as factura, j.amount as importe, j.status as estado, j.reimb_ref as reembolso
    from plone27_justifications j join plone27_grants g on g.id=j.grant_id
    join plone27_grant_programs gp on gp.id=g.program_id join plone27_accounts fa on fa.id=gp.funding_account
    where fa.bank_id=p_bank and (p_grant is null or j.grant_id=p_grant)) x $$;

create or replace function plone27_bk_justificar(p_bank uuid,p_grant uuid,p_tx uuid,p_invoice text,p_amount numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not exists(select 1 from plone27_grants g join plone27_grant_programs gp on gp.id=g.program_id
                join plone27_accounts fa on fa.id=gp.funding_account where g.id=p_grant and fa.bank_id=p_bank) then
    raise exception 'Concesión no encontrada en tu entidad';
  end if;
  return plone27_justify(p_grant,p_tx,p_invoice,p_amount,p_actor); end $$;

create or replace function plone27_bk_justificacion_pagar(p_bank uuid,p_just uuid,p_key text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not exists(select 1 from plone27_justifications j join plone27_grants g on g.id=j.grant_id
                join plone27_grant_programs gp on gp.id=g.program_id join plone27_accounts fa on fa.id=gp.funding_account
                where j.id=p_just and fa.bank_id=p_bank) then
    raise exception 'Justificación no encontrada en tu entidad';
  end if;
  return plone27_reimburse(p_key,p_just,p_actor); end $$;

create or replace function plone27_bk_justificacion_rechazar(p_bank uuid,p_just uuid,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare j plone27_justifications; begin
  select j.* into j from plone27_justifications j join plone27_grants g on g.id=j.grant_id
    join plone27_grant_programs gp on gp.id=g.program_id join plone27_accounts fa on fa.id=gp.funding_account
    where j.id=p_just and fa.bank_id=p_bank for update;
  if j.id is null then raise exception 'Justificación no encontrada en tu entidad'; end if;
  if j.status<>'pending' then raise exception 'Solo se rechazan justificaciones pendientes'; end if;
  update plone27_justifications set status='rejected' where id=p_just;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'justificacion_rechazada','justificacion',p_just::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- ---------- API de banco: reglas de uso ----------
create or replace function plone27_bk_politicas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select p.id, p.ambito, p.programa_id, gp.name as programa, p.tipos_destino as tipos, p.comercios, p.categorias, p.activa, p.creada
    from plone27_politicas_destino p left join plone27_grant_programs gp on gp.id=p.programa_id
    where p.bank_id=p_bank) x $$;

create or replace function plone27_bk_politica_crear(p_bank uuid,p_ambito text,p_programa uuid,p_tipos text[],p_comercios uuid[],p_categorias text[],p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; begin
  if p_ambito not in('rbu','programa') then raise exception 'Ámbito no válido'; end if;
  if p_ambito='programa' and not exists(select 1 from plone27_grant_programs gp join plone27_accounts fa on fa.id=gp.funding_account
     where gp.id=p_programa and fa.bank_id=p_bank) then raise exception 'Programa no encontrado en tu entidad'; end if;
  if p_ambito='rbu' then p_programa:=null; end if;
  if exists(select 1 from unnest(coalesce(p_categorias,'{}'::text[])) q where not exists(select 1 from plone27_categorias c where c.codigo=q and c.activa)) then
    raise exception 'Alguna categoría no existe';
  end if;
  if exists(select 1 from unnest(coalesce(p_comercios,'{}'::uuid[])) q where not exists(select 1 from plone27_accounts a where a.id=q and a.kind='business')) then
    raise exception 'Alguno de los comercios no es una cuenta de empresa';
  end if;
  if exists(select 1 from unnest(coalesce(p_tipos,'{}'::text[])) q where q not in('personal','business','shared','junior','system')) then
    raise exception 'Algún tipo de cuenta no existe';
  end if;
  -- una sola regla activa por ámbito: la nueva sustituye a la anterior
  update plone27_politicas_destino set activa=false where bank_id=p_bank and ambito=p_ambito and activa
    and (programa_id is not distinct from p_programa);
  insert into plone27_politicas_destino(bank_id,ambito,programa_id,tipos_destino,comercios,categorias)
    values(p_bank,p_ambito,p_programa,coalesce(p_tipos,'{}'),coalesce(p_comercios,'{}'),coalesce(p_categorias,'{}'))
    returning plone27_politicas_destino.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'politica_destino_crear','politica',pid::text,jsonb_build_object('ambito',p_ambito));
  return pid; end $$;

create or replace function plone27_bk_politica_desactivar(p_bank uuid,p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_politicas_destino set activa=false where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Regla no encontrada en tu entidad'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'politica_destino_desactivar','politica',p_id::text,'{}'::jsonb);
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

-- ==================== MIGRACIÓN (0045_plone27_ficha_empresa.sql) ====================
-- Placeta One · 0045 · Ficha de empresa: vínculo con la entidad institucional, organigrama, presupuesto por departamento
-- y nóminas pagadas. Requiere 0044. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

alter table plone27_empresas add column if not exists entidad_cip text references plone27_entidades(cip);
create unique index if not exists plone27_empresa_entidad_ux on plone27_empresas(entidad_cip) where entidad_cip is not null;

-- Vincula la entidad institucional a la empresa. Solo un titular activo de la empresa puede hacerlo.
create or replace function plone27_empresa_vincular_entidad(p_bank uuid,p_empresa uuid,p_cip text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  if not exists(select 1 from plone27_entidades x where x.cip=p_cip and x.bank_id=p_bank and x.activa) then
    raise exception 'Entidad institucional no encontrada o inactiva en tu entidad';
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=p_cip and o.id<>p_empresa) then
    raise exception 'Esa entidad ya está vinculada a otra empresa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede vincular una entidad';
  end if;
  update plone27_empresas set entidad_cip=p_cip where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_vincular_entidad','empresa',p_empresa::text,jsonb_build_object('cip',p_cip));
end $$;

-- Ficha completa. Ejercicio = año en curso. Pagado = gastos pagados; comprometido = propuestos o aprobados.
create or replace function plone27_empresa_ficha(p_bank uuid,p_empresa uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; ent plone27_entidades; ej int := extract(year from current_date)::int; r jsonb; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null then return null; end if;
  if e.entidad_cip is null then
    return jsonb_build_object('empresa',jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado),
      'entidad',null,'ejercicio',ej);
  end if;
  select * into ent from plone27_entidades where cip=e.entidad_cip;
  select jsonb_build_object(
    'empresa',jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado),
    'entidad',jsonb_build_object('cip',ent.cip,'nombre',ent.nombre,'activa',ent.activa),
    'ejercicio',ej,
    'organigrama',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'padre',u.padre,'tipo',u.tipo,'nombre',u.nombre,'codigo',u.codigo,'activa',u.activa) order by u.nombre),'[]'::jsonb)
                   from plone27_unidades u where u.entidad=ent.account_id),
    'departamentos',(select coalesce(jsonb_agg(to_jsonb(x) order by x.nombre),'[]'::jsonb) from (
        select u.id, u.nombre, u.tipo,
          coalesce((select sum(p.anual) from plone27_presupuestos p where p.unidad=u.id and p.ejercicio=ej),0) as presupuesto_anual,
          coalesce((select sum(g.importe) from plone27_gastos g where g.unidad=u.id and g.ejercicio=ej and g.estado='pagado'),0) as pagado,
          coalesce((select sum(g.importe) from plone27_gastos g where g.unidad=u.id and g.ejercicio=ej and g.estado in('propuesto','aprobado')),0) as comprometido
        from plone27_unidades u where u.entidad=ent.account_id) x),
    'nominas',(select coalesce(jsonb_agg(to_jsonb(x) order by x.periodo desc),'[]'::jsonb) from (
        select to_char(g.fecha,'YYYY-MM') as periodo, count(*) as pagos, sum(n.importe) as total
        from plone27_nominas_pagadas n join plone27_gastos g on g.id=n.gasto
        where g.entidad=ent.account_id group by to_char(g.fecha,'YYYY-MM')) x)
  ) into r;
  return r; end $$;

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

-- ==================== MIGRACIÓN (0046_plone27_api_banca_completa.sql) ====================
-- Placeta One · 0046 · Gestión completa por API de banco: delegaciones de organigrama y reclamaciones del banco acreedor.
-- Requiere 0045. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- La unidad debe pertenecer a la entidad (CIP) del banco que llama
create or replace function plone27_org_unidad_valida(p_bank uuid,p_cip text,p_unidad uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_unidades u join plone27_entidades e on e.account_id=u.entidad
    where u.id=p_unidad and e.cip=p_cip and e.bank_id=p_bank) $$;

create or replace function plone27_org_delegar(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_persona uuid,p_permiso text,
    p_limite numeric,p_hasta date,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_org_unidad_valida(p_bank,p_cip,p_unidad) then raise exception 'La unidad no pertenece a esta entidad'; end if;
  perform plone27_delegar(p_unidad,p_persona,p_permiso,p_limite,p_hasta,p_motivo,p_actor);
end $$;

create or replace function plone27_org_revocar_delegacion(p_bank uuid,p_cip text,p_actor uuid,p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not exists(select 1 from plone27_delegaciones d join plone27_unidades u on u.id=d.unidad
                join plone27_entidades e on e.account_id=u.entidad where d.id=p_id and e.cip=p_cip and e.bank_id=p_bank) then
    raise exception 'La delegación no pertenece a esta entidad';
  end if;
  perform plone27_revocar_delegacion(p_id,p_actor);
end $$;

-- Reclamaciones que afectan al banco: como acreedor (debe devolver) o como deudor (su cliente reclama)
create or replace function plone27_bk_disputas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.creada desc),'[]'::jsonb) from (
    select dsp.id, dsp.debt_id, dsp.estado, dsp.monto_reclamado, dsp.monto_devuelto, dsp.motivo, dsp.plazo_resolucion, dsp.creada,
      case when ca.bank_id=p_bank then 'acreedor' else 'deudor' end as rol
    from plone27_disputas dsp
    join plone27_debts dd on dd.id=dsp.debt_id
    join plone27_accounts ca on ca.id=dd.creditor_account
    join plone27_accounts da on da.id=dsp.account_id
    where ca.bank_id=p_bank or da.bank_id=p_bank) r $$;

-- Solo el banco acreedor resuelve. El operador identifica a la persona del banco: dos operadores distintos para devoluciones grandes.
create or replace function plone27_bk_disputa_resolver(p_bank uuid,p_id uuid,p_decision text,p_monto numeric,p_operador text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; ca uuid; begin
  select dd.* into d from plone27_disputas dsp join plone27_debts dd on dd.id=dsp.debt_id where dsp.id=p_id;
  if d.id is null then raise exception 'Reclamación no encontrada'; end if;
  select a.bank_id into ca from plone27_accounts a where a.id=d.creditor_account;
  if ca is distinct from p_bank then raise exception 'Solo el banco acreedor puede resolver esta reclamación'; end if;
  if coalesce(length(p_operador),0)<1 then raise exception 'Indica el operador que resuelve'; end if;
  return plone27_disputa_resolver(p_id,p_decision,p_monto,md5(p_bank::text||':'||p_operador)::uuid);
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

-- ==================== MIGRACIÓN (0047_plone27_cip_en_cuentas.sql) ====================
-- Placeta One · 0047 · El CIP de la entidad institucional se informa en las cuentas (me/accounts y bk/cuentas).
-- cip_origen: "cuenta" si la cuenta es la de la entidad; "empresa" si pertenece a una empresa vinculada a la entidad.
-- Requiere 0046. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Cambia la forma de la respuesta (dos columnas nuevas): hay que borrar la versión anterior
drop function if exists plone27_user_accounts(uuid,uuid);
create or replace function plone27_user_accounts(p_user uuid,p_bank uuid)
returns table(id uuid,iban text,nombre text,tipo text,rol text,saldo numeric,disponible numeric,cip text,cip_origen text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
  select a.id, a.iban, a.name, a.kind, m.role, b.booked, b.booked-b.reserved,
    coalesce(e.cip, ee.cip) as cip,
    case when e.cip is not null then 'cuenta' when ee.cip is not null then 'empresa' end as cip_origen
  from plone27_account_members m
  join plone27_accounts a on a.id=m.account_id
  join plone27_account_balances b on b.account_id=a.id
  left join plone27_entidades e on e.account_id=a.id
  left join lateral(
    select emp.entidad_cip as cip from plone27_empresa_cuentas ec
    join plone27_empresas emp on emp.id=ec.empresa_id
    where ec.account_id=a.id and emp.entidad_cip is not null limit 1) ee on true
  where m.user_id=p_user and a.status='active' and a.bank_id=p_bank
  order by a.created_at;
end $$;

-- Listado de cuentas de la entidad para el banco: mismo criterio de CIP
create or replace function plone27_bk_cuentas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.iban),'[]'::jsonb) from (
    select a.iban, a.name as nombre, a.kind as tipo, a.status as estado, plone27_available(a.id) as disponible,
      coalesce(e.cip, ee.cip) as cip,
      case when e.cip is not null then 'cuenta' when ee.cip is not null then 'empresa' end as cip_origen
    from plone27_accounts a
    left join plone27_entidades e on e.account_id=a.id
    left join lateral(
      select emp.entidad_cip as cip from plone27_empresa_cuentas ec
      join plone27_empresas emp on emp.id=ec.empresa_id
      where ec.account_id=a.id and emp.entidad_cip is not null limit 1) ee on true
    where a.bank_id=p_bank) x $$;

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

-- ==================== MIGRACIÓN (0048_plone27_empresa_crear_entidad.sql) ====================
-- Placeta One · 0048 · Crear la entidad institucional de una empresa desde la banca (y vincularla).
-- La entidad se crea sobre una cuenta de empresa de la propia empresa: esa cuenta recibe el CIP.
-- Requiere 0047. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

create or replace function plone27_empresa_crear_entidad(p_bank uuid,p_empresa uuid,p_iban text,p_nombre text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; v_nombre text; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank for update;
  if e.id is null or e.estado<>'activa' then raise exception 'Empresa no encontrada o no activa'; end if;
  if e.entidad_cip is not null then raise exception 'La empresa ya tiene una entidad vinculada (%)', e.entidad_cip; end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede crear su entidad';
  end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.iban=p_iban;
    if v_aid is null then raise exception 'La cuenta no pertenece a esta empresa'; end if;
  else
    select ec.account_id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status='active' order by a.created_at limit 1;
    if v_aid is null then raise exception 'La empresa no tiene cuentas de empresa'; end if;
  end if;
  v_nombre:=coalesce(nullif(p_nombre,''),e.nombre);
  select x.cip into v_cip from plone27_entidades x where x.account_id=v_aid;
  if v_cip is null then
    v_cip:=plone27_entidad_alta(p_bank,v_aid,v_nombre,p_actor);
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then
    raise exception 'Esa entidad ya está vinculada a otra empresa';
  end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_crear_entidad','empresa',p_empresa::text,jsonb_build_object('cip',v_cip,'cuenta',v_aid));
  return v_cip; end $$;

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

-- ==================== MIGRACIÓN (0049_plone27_datos_empresa_y_diagnostico.sql) ====================
-- Placeta One · 0049 · Identificador de empresa = CIP de la entidad. Vinculación automática por CIP.
-- En la plataforma no existe NIF para las entidades: el identificador de la empresa es el CIP.
-- Requiere 0048. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Si el identificador de la empresa es el CIP de una entidad activa de su mismo banco, se vincula sola
create or replace function plone27_empresa_autovincular(p_bank uuid,p_empresa uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; begin
  select * into e from plone27_empresas where id=p_empresa;
  if e.id is null or e.entidad_cip is not null then return; end if;
  select en.cip into v_cip from plone27_entidades en
    where en.cip=upper(e.identificador_fiscal) and en.bank_id=p_bank and en.activa;
  if v_cip is null then return; end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then return; end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'empresa_autovinculada','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
end $$;

-- Alta de empresa: intenta vincular la entidad por su identificador
create or replace function plone27_empresa_alta_completa(p_bank uuid,p_nombre text,p_fiscal text,p_persona uuid,p_ibans text[],p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare eid uuid; v_iban text; v_aid uuid; begin
  insert into plone27_empresas(bank_id,nombre,identificador_fiscal) values(p_bank,p_nombre,upper(p_fiscal))
    returning plone27_empresas.id into eid;
  foreach v_iban in array coalesce(p_ibans,'{}'::text[]) loop
    select a.id into v_aid from plone27_accounts a where a.iban=v_iban and a.bank_id=p_bank and a.kind='business' and a.status='active';
    if v_aid is null then raise exception 'La cuenta % no es una cuenta de empresa activa de tu entidad', v_iban; end if;
    insert into plone27_empresa_cuentas(empresa_id,account_id) values(eid,v_aid) on conflict do nothing;
  end loop;
  insert into plone27_empresa_titulares(empresa_id,persona,rol,motivo,alta_por)
    values(eid,p_persona,'titular','Alta de la empresa',p_actor);
  insert into plone27_account_members(account_id,user_id,role)
    select ec.account_id,p_persona,'holder' from plone27_empresa_cuentas ec where ec.empresa_id=eid on conflict do nothing;
  perform plone27_empresa_autovincular(p_bank,eid);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_alta','empresa',eid::text,jsonb_build_object('fiscal',upper(p_fiscal)));
  return eid; end $$;

-- La ficha muestra el vínculo con la entidad (entidad_cip)
create or replace function plone27_empresa_detalle(p_bank uuid,p_empresa uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare r jsonb; begin
  select jsonb_build_object('id',e.id,'nombre',e.nombre,'identificador_fiscal',e.identificador_fiscal,'estado',e.estado,'entidad_cip',e.entidad_cip,
    'titulares',(select coalesce(jsonb_agg(jsonb_build_object('dip',p.dip,'rol',t.rol,'desde',t.desde,'hasta',t.hasta) order by t.desde),'[]'::jsonb)
                 from plone27_empresa_titulares t join plone27_personas p on p.id=t.persona where t.empresa_id=e.id),
    'cuentas',(select coalesce(jsonb_agg(jsonb_build_object('iban',a.iban,'nombre',a.name) order by a.iban),'[]'::jsonb)
               from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id where ec.empresa_id=e.id),
    'pasarela',(select jsonb_build_object('client_id',pe.client_id,'activa',pe.activa) from plone27_empresa_pasarelas pe where pe.empresa_id=e.id),
    'contrato_version',(select max(c.version) from plone27_empresa_contratos c where c.empresa_id=e.id))
  into r from plone27_empresas e where e.id=p_empresa and e.bank_id=p_bank;
  return r; end $$;

-- Corregir nombre e identificador (el identificador es el CIP de la entidad). Solo un titular activo.
create or replace function plone27_empresa_datos_set(p_bank uuid,p_empresa uuid,p_nombre text,p_fiscal text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede corregir sus datos';
  end if;
  if coalesce(length(p_nombre),0) not between 2 and 120 then raise exception 'Nombre entre 2 y 120 caracteres'; end if;
  if coalesce(length(p_fiscal),0) not between 5 and 20 then raise exception 'Identificador entre 5 y 20 caracteres'; end if;
  update plone27_empresas set nombre=p_nombre, identificador_fiscal=upper(p_fiscal) where id=p_empresa and bank_id=p_bank;
  if not found then raise exception 'Empresa no encontrada'; end if;
  perform plone27_empresa_autovincular(p_bank,p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_datos_set','empresa',p_empresa::text,jsonb_build_object('nombre',p_nombre));
end $$;

-- Empresas que ya tienen como identificador el CIP de una entidad de su banco: se vinculan ahora
do $$ declare r record; begin
  for r in select e.id, e.bank_id from plone27_empresas e where e.entidad_cip is null loop
    perform plone27_empresa_autovincular(r.bank_id, r.id);
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

-- ==================== MIGRACIÓN (0050_plone27_crear_entidad_identificador.sql) ====================
-- Placeta One · 0050 · Crear la entidad de una empresa y hacer que su identificador sea el CIP nuevo.
-- Mensaje claro cuando el CIP indicado no existe en el banco. Requiere 0049. Idempotente. NO ejecutado en PostgreSQL.

create or replace function plone27_empresa_vincular_entidad(p_bank uuid,p_empresa uuid,p_cip text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null then raise exception 'Empresa no encontrada'; end if;
  if not exists(select 1 from plone27_entidades x where x.cip=upper(p_cip) and x.bank_id=p_bank and x.activa) then
    raise exception 'La entidad % no existe o está inactiva en tu banco. Si no tienes entidad, créala sobre una cuenta de la empresa', p_cip;
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=upper(p_cip) and o.id<>p_empresa) then
    raise exception 'Esa entidad ya está vinculada a otra empresa';
  end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede vincular una entidad';
  end if;
  update plone27_empresas set entidad_cip=upper(p_cip), identificador_fiscal=upper(p_cip) where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_vincular_entidad','empresa',p_empresa::text,jsonb_build_object('cip',p_cip));
end $$;

create or replace function plone27_empresa_crear_entidad(p_bank uuid,p_empresa uuid,p_iban text,p_nombre text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; v_nombre text; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank for update;
  if e.id is null or e.estado<>'activa' then raise exception 'Empresa no encontrada o no activa'; end if;
  if e.entidad_cip is not null then raise exception 'La empresa ya tiene una entidad vinculada (%)', e.entidad_cip; end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede crear su entidad';
  end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.iban=p_iban;
    if v_aid is null then raise exception 'La cuenta no pertenece a esta empresa'; end if;
  else
    select ec.account_id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status='active' order by a.created_at limit 1;
    if v_aid is null then raise exception 'La empresa no tiene cuentas de empresa'; end if;
  end if;
  v_nombre:=coalesce(nullif(p_nombre,''),e.nombre);
  select x.cip into v_cip from plone27_entidades x where x.account_id=v_aid;
  if v_cip is null then
    v_cip:=plone27_entidad_alta(p_bank,v_aid,v_nombre,p_actor);
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then
    raise exception 'Esa entidad ya está vinculada a otra empresa';
  end if;
  update plone27_empresas set entidad_cip=v_cip, identificador_fiscal=v_cip where id=p_empresa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_crear_entidad','empresa',p_empresa::text,jsonb_build_object('cip',v_cip,'cuenta',v_aid));
  return v_cip; end $$;

-- ==================== MIGRACIÓN (0051_plone27_empresa_entidad_por_cuenta.sql) ====================
-- Placeta One · 0051 · Empresa y entidad son lo mismo: si una cuenta de la empresa ya es una entidad del banco, se vincula.
-- Crear la entidad reutiliza la existente. Mensajes que dicen qué empresa ya tiene la entidad. Requiere 0050. Idempotente.

-- Vinculación automática: por identificador (CIP) o por cuenta de la empresa que ya es una entidad
create or replace function plone27_empresa_autovincular(p_bank uuid,p_empresa uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; begin
  select * into e from plone27_empresas where id=p_empresa;
  if e.id is null or e.entidad_cip is not null then return; end if;
  select en.cip into v_cip from plone27_entidades en
    where en.cip=upper(e.identificador_fiscal) and en.bank_id=p_bank and en.activa;
  if v_cip is null then
    select en.cip into v_cip from plone27_empresa_cuentas ec
      join plone27_entidades en on en.account_id=ec.account_id
      where ec.empresa_id=p_empresa and en.bank_id=p_bank and en.activa limit 1;
  end if;
  if v_cip is null then return; end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then return; end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=p_bank and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'empresa_autovinculada','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
end $$;

-- Crear la entidad de la empresa: reutiliza la entidad que ya exista en esa cuenta
create or replace function plone27_empresa_crear_entidad(p_bank uuid,p_empresa uuid,p_iban text,p_nombre text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; v_nombre text; v_activa boolean; v_otra text; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank for update;
  if e.id is null or e.estado<>'activa' then raise exception 'Empresa no encontrada o no activa'; end if;
  if e.entidad_cip is not null then raise exception 'La empresa ya tiene una entidad vinculada (%)', e.entidad_cip; end if;
  if not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede crear su entidad';
  end if;
  if coalesce(p_iban,'')<>'' then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.iban=p_iban;
    if v_aid is null then raise exception 'La cuenta no pertenece a esta empresa'; end if;
  else
    select ec.account_id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status='active' order by a.created_at limit 1;
    if v_aid is null then raise exception 'La empresa no tiene cuentas de empresa'; end if;
  end if;
  -- ¿La cuenta ya es una entidad? Se reutiliza.
  select x.cip, x.activa into v_cip, v_activa from plone27_entidades x where x.account_id=v_aid and x.bank_id=p_bank;
  if v_cip is null then
    v_nombre:=coalesce(nullif(p_nombre,''),e.nombre);
    v_cip:=plone27_entidad_alta(p_bank,v_aid,v_nombre,p_actor);
  elsif not v_activa then
    raise exception 'La entidad % de esa cuenta está inactiva en tu banco', v_cip;
  end if;
  select o.nombre into v_otra from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa;
  if v_otra is not null then
    raise exception 'La entidad % ya está vinculada a la empresa "%"', v_cip, v_otra;
  end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=p_bank and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_crear_entidad','empresa',p_empresa::text,jsonb_build_object('cip',v_cip,'cuenta',v_aid));
  return v_cip; end $$;

-- Empresas existentes: se vinculan ahora si su cuenta ya es una entidad del banco
do $$ declare r record; begin
  for r in select e.id, e.bank_id from plone27_empresas e where e.entidad_cip is null loop
    perform plone27_empresa_autovincular(r.bank_id, r.id);
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

-- ==================== MIGRACIÓN (0052_plone27_empresa_es_entidad.sql) ====================
-- Placeta One · 0052 · La empresa es su entidad institucional: se crea automáticamente al añadir su primera cuenta de empresa.
-- Requiere 0051. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Garantiza la entidad de la empresa: reutiliza la que ya exista en una de sus cuentas, o la crea sobre la primera cuenta de empresa
create or replace function plone27_empresa_asegurar_entidad(p_empresa uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; v_aid uuid; begin
  select * into e from plone27_empresas where id=p_empresa for update;
  if e.id is null then return null; end if;
  if e.entidad_cip is not null then return e.entidad_cip; end if;
  select en.cip into v_cip from plone27_empresa_cuentas ec
    join plone27_entidades en on en.account_id=ec.account_id
    where ec.empresa_id=p_empresa and en.bank_id=e.bank_id and en.activa limit 1;
  if v_cip is null then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status='active' and a.kind='business' order by a.created_at limit 1;
    if v_aid is null then return null; end if;
    v_cip:=plone27_entidad_alta(e.bank_id,v_aid,e.nombre,p_actor);
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then return null; end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=e.bank_id and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_entidad_automatica','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
  return v_cip; end $$;

-- Cada cuenta nueva de empresa asegura la entidad de la empresa
create or replace function plone27_trg_empresa_cuentas_entidad() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  perform plone27_empresa_asegurar_entidad(new.empresa_id,null);
  return new; end $$;
drop trigger if exists trg_empresa_cuentas_entidad on plone27_empresa_cuentas;
drop trigger if exists trg_empresa_cuentas_entidad on plone27_empresa_cuentas;
create trigger trg_empresa_cuentas_entidad after insert on plone27_empresa_cuentas
  for each row execute function plone27_trg_empresa_cuentas_entidad();

-- Empresas existentes con cuentas y sin entidad: se resuelven ahora
do $$ declare r record; begin
  for r in select id from plone27_empresas where entidad_cip is null loop
    perform plone27_empresa_asegurar_entidad(r.id,null);
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

-- ==================== MIGRACIÓN (0053_plone27_empresa_cuentas_entidad_forzable.sql) ====================
-- Placeta One · 0053 · Añadir cuentas a la empresa y crear su entidad de forma explícita.
-- La creación automática no hace fallar el alta: si no puede, deja constancia y el botón la fuerza. Requiere 0052. Idempotente.

-- Garantiza la entidad: reutiliza la que ya exista en una cuenta de la empresa, o la crea sobre la mejor cuenta disponible
create or replace function plone27_empresa_asegurar_entidad(p_empresa uuid,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_cip text; v_aid uuid; v_act boolean; begin
  select * into e from plone27_empresas where id=p_empresa for update;
  if e.id is null then return null; end if;
  if e.entidad_cip is not null then return e.entidad_cip; end if;
  select en.cip into v_cip from plone27_empresa_cuentas ec join plone27_entidades en on en.account_id=ec.account_id
    where ec.empresa_id=p_empresa and en.bank_id=e.bank_id and en.activa limit 1;
  if v_cip is null then
    select a.id into v_aid from plone27_empresa_cuentas ec join plone27_accounts a on a.id=ec.account_id
      where ec.empresa_id=p_empresa and a.status is distinct from 'closed'
      order by (a.kind='business') desc, (a.status='active') desc, a.created_at limit 1;
    if v_aid is null then return null; end if;
    select x.cip, x.activa into v_cip, v_act from plone27_entidades x where x.account_id=v_aid;
    if v_cip is not null and not v_act then raise exception 'La entidad % de esa cuenta está inactiva', v_cip; end if;
    if v_cip is null then v_cip:=plone27_entidad_alta(e.bank_id,v_aid,e.nombre,p_actor); end if;
  end if;
  if exists(select 1 from plone27_empresas o where o.entidad_cip=v_cip and o.id<>p_empresa) then
    raise exception 'La entidad % ya está vinculada a otra empresa', v_cip;
  end if;
  update plone27_empresas set entidad_cip=v_cip where id=p_empresa;
  update plone27_empresas set identificador_fiscal=v_cip where id=p_empresa
    and not exists(select 1 from plone27_empresas o where o.bank_id=e.bank_id and o.identificador_fiscal=v_cip and o.id<>p_empresa);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_entidad','empresa',p_empresa::text,jsonb_build_object('cip',v_cip));
  return v_cip; end $$;

-- Al insertar una cuenta de empresa se intenta asegurar la entidad; si falla, no se bloquea el alta
create or replace function plone27_trg_empresa_cuentas_entidad() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  begin
    perform plone27_empresa_asegurar_entidad(new.empresa_id,null);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_entidad_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  return new; end $$;

-- Añadir una cuenta a la empresa: da permisos a sus titulares y asegura la entidad
create or replace function plone27_empresa_cuenta_anadir(p_bank uuid,p_empresa uuid,p_iban text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null or e.estado<>'activa' then raise exception 'Empresa no encontrada o no activa'; end if;
  if p_actor is not null and not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede añadir cuentas';
  end if;
  select a.id into v_aid from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if v_aid is null then raise exception 'La cuenta % no existe en tu banco', p_iban; end if;
  insert into plone27_empresa_cuentas(empresa_id,account_id) values(p_empresa,v_aid) on conflict do nothing;
  insert into plone27_account_members(account_id,user_id,role)
    select v_aid, t.persona, case t.rol when 'titular' then 'holder' when 'autorizado' then 'coholder' else 'authorized' end
    from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.hasta is null
    on conflict do nothing;
  v_cip:=plone27_empresa_asegurar_entidad(p_empresa,p_actor);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_cuenta_anadir','empresa',p_empresa::text,jsonb_build_object('iban',p_iban));
  return v_cip; end $$;

-- Empresas existentes sin entidad: se resuelven ahora
do $$ declare r record; begin
  for r in select id from plone27_empresas where entidad_cip is null loop
    begin
      perform plone27_empresa_asegurar_entidad(r.id,null);
    exception when others then
      insert into plone27_audit_log(actor,action,entity,entity_id,detail)
        values(null,'empresa_entidad_pendiente','empresa',r.id::text,jsonb_build_object('error',sqlerrm));
    end;
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

-- ==================== MIGRACIÓN (0054_plone27_entidades_automaticas.sql) ====================
-- Placeta One · 0054 · La entidad de cada empresa se crea y se repara sola (disparador + cron cada 15 minutos).
-- Los errores quedan en la auditoría y se muestran en la ficha. Requiere 0053. Idempotente. NO ejecutado en PostgreSQL.

-- Repara todas las empresas activas con cuentas y sin entidad. Devuelve cuántas ha resuelto.
create or replace function plone27_empresa_reparar_entidades() returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; n int:=0; begin
  for r in select e.id from plone27_empresas e
           where e.entidad_cip is null and e.estado='activa'
             and exists(select 1 from plone27_empresa_cuentas ec where ec.empresa_id=e.id) loop
    begin
      if plone27_empresa_asegurar_entidad(r.id,null) is not null then n:=n+1; end if;
    exception when others then
      insert into plone27_audit_log(actor,action,entity,entity_id,detail)
        values(null,'empresa_entidad_pendiente','empresa',r.id::text,jsonb_build_object('error',sqlerrm));
    end;
  end loop;
  return n; end $$;

-- Pasada inicial sobre lo que ya existe
do $$ begin perform plone27_empresa_reparar_entidades(); end $$;

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

-- ==================== MIGRACIÓN (0055_plone27_organigrama_inicial.sql) ====================
-- Placeta One · 0055 · La entidad de cada empresa nace con su organigrama inicial: unidad raíz, puesto de titular
-- con todos los permisos y nombramiento del titular de la empresa. Sin esto nadie puede cambiar el organigrama (422).
-- Requiere 0054. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Crea la unidad raíz, el puesto de titular y el nombramiento, solo si la entidad aún no tiene unidades
create or replace function plone27_empresa_bootstrap_organigrama(p_empresa uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; ent plone27_entidades; per uuid; uid uuid; pid uuid; acc text; begin
  select * into e from plone27_empresas where id=p_empresa;
  if e.id is null or e.entidad_cip is null then return; end if;
  select * into ent from plone27_entidades where cip=e.entidad_cip;
  if ent.account_id is null then return; end if;
  if exists(select 1 from plone27_unidades u where u.entidad=ent.account_id) then return; end if;
  select t.persona into per from plone27_empresa_titulares t
    where t.empresa_id=p_empresa and t.rol='titular' and t.hasta is null order by t.desde limit 1;
  if per is null then return; end if;
  uid:=plone27_unidad_alta(ent.account_id,'junta',null,ent.nombre,null,null);
  pid:=plone27_puesto_alta(uid,'Titular',5,null);
  foreach acc in array array['proponer','aprobar','ejecutar','presupuestar','reasignar','retribuir','organigrama','cerrar'] loop
    insert into plone27_puesto_permisos(puesto,accion) values(pid,acc) on conflict do nothing;
  end loop;
  perform plone27_nombrar(pid,per,'Titular de la empresa (organigrama inicial)',null);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'organigrama_inicial','empresa',p_empresa::text,jsonb_build_object('unidad',uid,'puesto',pid));
end $$;

-- Al crear o asegurar la entidad de una cuenta de empresa: se deja el organigrama inicial
create or replace function plone27_trg_empresa_cuentas_entidad() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  begin
    perform plone27_empresa_asegurar_entidad(new.empresa_id,null);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_entidad_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  begin
    perform plone27_empresa_bootstrap_organigrama(new.empresa_id);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_organigrama_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  return new; end $$;

-- Al dar de alta un titular: si la entidad aún no tiene organigrama, se crea con él como titular
create or replace function plone27_trg_empresa_titular_organigrama() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  begin
    perform plone27_empresa_bootstrap_organigrama(new.empresa_id);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_organigrama_pendiente','empresa',new.empresa_id::text,jsonb_build_object('error',sqlerrm));
  end;
  return new; end $$;
drop trigger if exists trg_empresa_titular_organigrama on plone27_empresa_titulares;
drop trigger if exists trg_empresa_titular_organigrama on plone27_empresa_titulares;
create trigger trg_empresa_titular_organigrama after insert on plone27_empresa_titulares
  for each row execute function plone27_trg_empresa_titular_organigrama();

-- Añadir una cuenta: también deja el organigrama inicial
create or replace function plone27_empresa_cuenta_anadir(p_bank uuid,p_empresa uuid,p_iban text,p_actor uuid) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare e plone27_empresas; v_aid uuid; v_cip text; begin
  select * into e from plone27_empresas where id=p_empresa and bank_id=p_bank;
  if e.id is null or e.estado<>'activa' then raise exception 'Empresa no encontrada o no activa'; end if;
  if p_actor is not null and not exists(select 1 from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.persona=p_actor and t.rol='titular' and t.hasta is null) then
    raise exception 'Solo un titular de la empresa puede añadir cuentas';
  end if;
  select a.id into v_aid from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if v_aid is null then raise exception 'La cuenta % no existe en tu banco', p_iban; end if;
  insert into plone27_empresa_cuentas(empresa_id,account_id) values(p_empresa,v_aid) on conflict do nothing;
  insert into plone27_account_members(account_id,user_id,role)
    select v_aid, t.persona, case t.rol when 'titular' then 'holder' when 'autorizado' then 'coholder' else 'authorized' end
    from plone27_empresa_titulares t where t.empresa_id=p_empresa and t.hasta is null
    on conflict do nothing;
  v_cip:=plone27_empresa_asegurar_entidad(p_empresa,p_actor);
  begin
    perform plone27_empresa_bootstrap_organigrama(p_empresa);
  exception when others then
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(null,'empresa_organigrama_pendiente','empresa',p_empresa::text,jsonb_build_object('error',sqlerrm));
  end;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'empresa_cuenta_anadir','empresa',p_empresa::text,jsonb_build_object('iban',p_iban));
  return v_cip; end $$;

-- Empresas existentes con entidad y titular: se completa su organigrama inicial
do $$ declare r record; begin
  for r in select id from plone27_empresas where entidad_cip is not null loop
    begin
      perform plone27_empresa_bootstrap_organigrama(r.id);
    exception when others then
      insert into plone27_audit_log(actor,action,entity,entity_id,detail)
        values(null,'empresa_organigrama_pendiente','empresa',r.id::text,jsonb_build_object('error',sqlerrm));
    end;
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

-- ==================== MIGRACIÓN (0056_plone27_organigrama_padre_por_defecto.sql) ====================
-- Placeta One · 0056 · Una unidad sin padre se cuelga automáticamente de la Junta raíz de la entidad.
-- Antes, crear un departamento sin padre respondía 422 "Una unidad de tipo necesita una unidad padre".
-- Requiere 0055. Idempotente. NO ejecutado en PostgreSQL.

create or replace function plone27_org_unidad_nueva(p_bank uuid,p_cip text,p_actor uuid,p_tipo text,p_padre uuid,p_nombre text,p_codigo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if p_padre is null and p_tipo<>'junta' then
    select u.id into p_padre from plone27_unidades u
      where u.entidad=ent and u.activa and u.padre is null order by u.creada limit 1;
  end if;
  if p_padre is not null and not exists(select 1 from plone27_unidades u where u.id=p_padre and u.entidad=ent and u.activa) then
    raise exception 'Unidad superior no válida o cerrada';
  end if;
  return plone27_unidad_alta(ent,p_tipo,p_padre,p_nombre,p_codigo,p_actor); end $$;

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

-- ==================== MIGRACIÓN (0057_plone27_organigrama_raiz_automatica.sql) ====================
-- Placeta One · 0057 · Si la entidad no tiene Junta raíz, se crea al hacer falta. Una unidad sin padre cuelga de esa raíz.
-- Requiere 0056. Idempotente. NO ejecutado en PostgreSQL.

create or replace function plone27_org_unidad_nueva(p_bank uuid,p_cip text,p_actor uuid,p_tipo text,p_padre uuid,p_nombre text,p_codigo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'organigrama') then raise exception 'Sin permiso para cambiar el organigrama'; end if;
  if p_padre is null and p_tipo<>'junta' then
    select u.id into p_padre from plone27_unidades u
      where u.entidad=ent and u.activa and u.tipo='junta' and u.padre is null order by u.creada limit 1;
    if p_padre is null then
      p_padre:=plone27_unidad_alta(ent,'junta',null,(select e.nombre from plone27_entidades e where e.account_id=ent),null,p_actor);
    end if;
  end if;
  if p_padre is not null and not exists(select 1 from plone27_unidades u where u.id=p_padre and u.entidad=ent and u.activa) then
    raise exception 'Unidad superior no válida o cerrada';
  end if;
  return plone27_unidad_alta(ent,p_tipo,p_padre,p_nombre,p_codigo,p_actor); end $$;

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

-- ==================== MIGRACIÓN (0058_plone27_complementos_contrato_nexe.sql) ====================
-- Placeta One · 0058 · Complementos de actividad asignables a un contrato, y conceptos por periodo para NEXE.
-- Requiere 0057. Idempotente. NO ejecutado en PostgreSQL. No modifica el motor de nóminas existente.

-- Catálogo de complementos de cada entidad
create table if not exists plone27_complementos(
  id uuid primary key default gen_random_uuid(),
  entidad uuid not null references plone27_entidades(account_id),
  codigo text not null check(codigo ~ '^[A-Z0-9_]{2,20}$'),
  nombre text not null check(length(nombre) between 3 and 120),
  tipo text not null default 'fijo' check(tipo in('fijo','variable')),
  importe_base numeric(18,2) check(importe_base is null or importe_base>=0),
  activo boolean not null default true,
  creado timestamptz not null default now(),
  unique(entidad,codigo));

-- Asignación de un complemento a un contrato (retribución), con vigencia
create table if not exists plone27_complementos_contrato(
  id uuid primary key default gen_random_uuid(),
  retribucion uuid not null references plone27_retribuciones(id),
  complemento uuid not null references plone27_complementos(id),
  importe numeric(18,2) not null check(importe>0),
  desde date not null default current_date,
  hasta date,
  motivo text not null check(length(motivo) between 5 and 300),
  asignado_por uuid,
  creado timestamptz not null default now(),
  check(hasta is null or hasta>=desde));
create unique index if not exists plone27_complemento_activo_ux on plone27_complementos_contrato(retribucion,complemento) where hasta is null;

create or replace function plone27_bk_complemento_crear(p_bank uuid,p_cip text,p_actor uuid,p_codigo text,p_nombre text,p_tipo text,p_importe numeric) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; cid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'retribuir') then raise exception 'Sin permiso para retribuir en esta entidad'; end if;
  if p_tipo not in('fijo','variable') then raise exception 'Tipo de complemento no válido (fijo o variable)'; end if;
  insert into plone27_complementos(entidad,codigo,nombre,tipo,importe_base) values(ent,upper(p_codigo),p_nombre,p_tipo,p_importe)
    returning plone27_complementos.id into cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'complemento_crear','complemento',cid::text,jsonb_build_object('codigo',upper(p_codigo)));
  return cid; end $$;

create or replace function plone27_bk_complementos(p_bank uuid,p_cip text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.codigo),'[]'::jsonb) from (
    select c.id, c.codigo, c.nombre, c.tipo, c.importe_base, c.activo from plone27_complementos c where c.entidad=ent) x);
end $$;

create or replace function plone27_bk_complemento_asignar(p_bank uuid,p_cip text,p_actor uuid,p_retribucion uuid,p_complemento uuid,
    p_importe numeric,p_desde date,p_hasta date,p_motivo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; c plone27_complementos; r plone27_retribuciones; imp numeric; aid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'retribuir') then raise exception 'Sin permiso para retribuir en esta entidad'; end if;
  select * into r from plone27_retribuciones where id=p_retribucion and entidad=ent;
  if r.id is null then raise exception 'Contrato (retribución) no encontrado en la entidad'; end if;
  select * into c from plone27_complementos where id=p_complemento and entidad=ent and activo;
  if c.id is null then raise exception 'Complemento no encontrado o inactivo'; end if;
  imp:=coalesce(p_importe,c.importe_base);
  if imp is null or imp<=0 then raise exception 'Indica el importe del complemento'; end if;
  if coalesce(length(p_motivo),0)<5 then raise exception 'El motivo debe tener al menos 5 caracteres'; end if;
  if exists(select 1 from plone27_complementos_contrato cc where cc.retribucion=p_retribucion and cc.complemento=p_complemento and cc.hasta is null) then
    raise exception 'Este complemento ya está asignado a ese contrato: retíralo antes';
  end if;
  insert into plone27_complementos_contrato(retribucion,complemento,importe,desde,hasta,motivo,asignado_por)
    values(p_retribucion,p_complemento,imp,coalesce(p_desde,current_date),p_hasta,p_motivo,p_actor)
    returning plone27_complementos_contrato.id into aid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'complemento_asignar','asignacion',aid::text,jsonb_build_object('importe',imp));
  return aid; end $$;

create or replace function plone27_bk_complemento_retirar(p_bank uuid,p_cip text,p_actor uuid,p_asignacion uuid,p_hasta date) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; n int; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_tiene_en_entidad(p_actor,ent,'retribuir') then raise exception 'Sin permiso para retribuir en esta entidad'; end if;
  with x as(update plone27_complementos_contrato cc set hasta=coalesce(p_hasta,current_date)
            from plone27_retribuciones r
            where cc.id=p_asignacion and cc.hasta is null and r.id=cc.retribucion and r.entidad=ent returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Asignación no encontrada o ya retirada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'complemento_retirar','asignacion',p_asignacion::text,jsonb_build_object('hasta',coalesce(p_hasta,current_date)));
end $$;

-- Conceptos de un periodo (AAAA-MM): lo que NEXE necesita para emitir la nómina
create or replace function plone27_bk_conceptos_periodo(p_bank uuid,p_cip text,p_periodo text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; ini date; fin date; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if p_periodo is null or p_periodo !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then raise exception 'Periodo no válido (AAAA-MM)'; end if;
  ini:=to_date(p_periodo||'-01','YYYY-MM-DD');
  fin:=(ini + interval '1 month' - interval '1 day')::date;
  return (select coalesce(jsonb_agg(to_jsonb(x) order by x.persona, x.tipo, x.concepto),'[]'::jsonb) from (
    select p.dip as persona, 'retribucion'::text as tipo, null::text as codigo, r.concepto as concepto, r.importe as importe, p_periodo::text as periodo
      from plone27_retribuciones r join plone27_personas p on p.id=r.persona
      where r.entidad=ent and r.desde<=fin and (r.hasta is null or r.hasta>=ini)
    union all
    select p.dip, 'complemento'::text, c.codigo, c.nombre, cc.importe, p_periodo::text
      from plone27_complementos_contrato cc
      join plone27_retribuciones r on r.id=cc.retribucion
      join plone27_complementos c on c.id=cc.complemento
      join plone27_personas p on p.id=r.persona
      where r.entidad=ent and cc.desde<=fin and (cc.hasta is null or cc.hasta>=ini)
  ) x);
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

-- ==================== DATOS DE LA NORMA Y CUENTAS (0011_seed_norma_tributos_2027.sql) ====================
-- Placeta One · seed 0011 · Norma de tributos (Código Normativo | Tributos, Junta 26/09/2026)
-- Ejecutar en staging y luego en producción, DESPUÉS de la migración 0011. No va en CI (acceptance.sql usa IGF e IRM).
-- Todo entra como BORRADOR: nada se aplica hasta que una persona distinta del autor lo publique con plone27_tax_publish.
-- Vigencia: 1 de enero de 2027 (título del documento: «de cara al 2027»). Supuesto a confirmar.

-- 1) Cuentas de sistema: Cuenta de Reserva del Grupo (Art. 4.4 y 4.5) y Placeta Junior (pagos asumidos, Art. T19–T20)
do $$ declare bk uuid; r uuid; pj uuid; begin
  select id into bk from plone27_banks where code='0000';
  if not exists(select 1 from plone27_config where key='cuenta_reserva') then
    r:=(plone27_open_account(bk,'system','Cuenta de Reserva del Grupo',null,null)->>'id')::uuid;
    insert into plone27_config(key,value) values('cuenta_reserva',r::text);
  end if;
  if not exists(select 1 from plone27_config where key='cuenta_placeta_junior') then
    pj:=(plone27_open_account(bk,'business','Placeta Junior · pagos asumidos',null,null)->>'id')::uuid;
    insert into plone27_config(key,value) values('cuenta_placeta_junior',pj::text);
  end if;
end $$;

-- 2) Impuestos y cotizaciones: todos recaudan en la Cuenta de Reserva (Art. 4.4 para IVA; mismo criterio para el resto, a confirmar)
insert into plone27_tax_rules(code,name,collector_account,max_rate) select c,n,null,m from (values
  ('IVA','IVA (Art. T26, 4.4)',12::numeric),('IRM','IRM (Art. T29)',5::numeric),('IGF','IGF (Art. T32)',null::numeric),
  ('IRP','IRP (Art. T35)',null::numeric),('IBA','IBA (Art. T38)',null::numeric),('IAEP','IAEP (Art. T41)',null::numeric),
  ('ITP','ITP (Art. T44)',null::numeric),('IPE','IPE (Art. T47)',null::numeric),
  ('COT_EMP','Cotización empresa (Art. 4.5)',null::numeric),('COT_TRA','Cotización trabajador (Art. 4.5)',null::numeric)
) as t(c,n,m) on conflict(code) do nothing;
update plone27_tax_rules set collector_account=(select nullif(value,'')::uuid from plone27_config where key='cuenta_reserva')
  where collector_account is null;

-- 3) Versiones en borrador (método y tipo según la norma; los tramos van abajo)
insert into plone27_tax_rule_versions(rule_id,version,method,rate,scope_op,valid_from,reason,status)
select r.id,x.ver,x.method,x.rate,x.scope,date '2027-01-01',x.reason,'draft'
from plone27_tax_rules r join (values
  ('IVA',1,'percent',12::numeric,null::text,'Art. T26 y 4.4: 12 % sobre la base'),
  ('IRM',1,'percent',1::numeric,null::text,'Art. T29.2: tipo ordinario 1 %'),
  ('IRM',2,'percent',5::numeric,'extraordinario','Art. T29.3–4: tipo extraordinario solo en supuestos expresos'),
  ('IGF',1,'brackets',0::numeric,null::text,'Art. T32–T33: progresivo por tramos'),
  ('IRP',1,'brackets',0::numeric,null::text,'Art. T35–T36: progresivo por tramos'),
  ('IBA',1,'brackets',0::numeric,null::text,'Art. T38–T39: progresivo por tramos'),
  ('IAEP',1,'fixed',0::numeric,'microactividad','Art. T41: cuota mensual por categoría'),
  ('IAEP',2,'fixed',10::numeric,'pequena','Art. T41: cuota mensual por categoría'),
  ('IAEP',3,'fixed',25::numeric,'mediana','Art. T41: cuota mensual por categoría'),
  ('IAEP',4,'fixed',50::numeric,'grande','Art. T41: cuota mensual por categoría'),
  ('IAEP',5,'fixed',100::numeric,'especial','Art. T41: cuota mensual por categoría'),
  ('ITP',1,'brackets',0::numeric,null::text,'Art. T44–T45: progresivo por tramos'),
  ('IPE',1,'brackets',0::numeric,null::text,'Art. T47–T48: progresivo por tramos'),
  ('COT_EMP',1,'bracket_flat',0::numeric,null::text,'Art. 4.5: tipo del tramo sobre el bruto'),
  ('COT_TRA',1,'bracket_flat',0::numeric,null::text,'Art. 4.5: tipo del tramo sobre el bruto')
) as x(code,ver,method,rate,scope,reason) on r.code=x.code
on conflict(rule_id,version) do nothing;

-- 4) Tramos (desde, hasta, tipo %). Hasta null = sin tope.
insert into plone27_tax_brackets(version_id,from_amount,to_amount,rate)
select v.id,b.f,b.t,b.r from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id
join (values
  ('IGF',1,0::numeric,50000::numeric,0::numeric),('IGF',1,50000,100000,2),('IGF',1,100000,150000,4.20),('IGF',1,150000,200000,6.40),
  ('IGF',1,200000,300000,8.60),('IGF',1,300000,500000,12.50),('IGF',1,500000,750000,15.50),('IGF',1,750000,1000000,18.50),('IGF',1,1000000,null::numeric,21.50),
  ('IRP',1,0::numeric,500::numeric,0::numeric),('IRP',1,500,1000,5),('IRP',1,1000,2000,10),('IRP',1,2000,3500,15),('IRP',1,3500,5000,20),
  ('IRP',1,5000,7500,25),('IRP',1,7500,10000,30),('IRP',1,10000,15000,35),('IRP',1,15000,null::numeric,40),
  ('IBA',1,0::numeric,500::numeric,0::numeric),('IBA',1,500,2000,3),('IBA',1,2000,5000,5),('IBA',1,5000,10000,8),
  ('IBA',1,10000,25000,10),('IBA',1,25000,50000,12),('IBA',1,50000,null::numeric,15),
  ('ITP',1,0::numeric,5000::numeric,0::numeric),('ITP',1,5000,25000,3.50),('ITP',1,25000,100000,7),('ITP',1,100000,500000,10.50),('ITP',1,500000,null::numeric,21.50),
  ('IPE',1,0::numeric,10000::numeric,0::numeric),('IPE',1,10000,500000,12),('IPE',1,500000,2000000,16),('IPE',1,2000000,10000000,20),('IPE',1,10000000,null::numeric,24),
  ('COT_EMP',1,0::numeric,1700::numeric,7.50::numeric),('COT_EMP',1,1700,3000,10.50),('COT_EMP',1,3000,null::numeric,17.50),
  ('COT_TRA',1,0::numeric,1700::numeric,7.50::numeric),('COT_TRA',1,1700,3000,10.50),('COT_TRA',1,3000,null::numeric,17.50)
) as b(code,ver,f,t,r) on b.code=ru.code and b.ver=v.version
on conflict do nothing;

-- 5) Autocomprobación: los ejemplos numéricos del propio Código deben salir exactos. Si no, el seed se para.
do $$ declare
  v_iva uuid; v_irm uuid; v_igf uuid; v_irp uuid; v_iba uuid; v_itp uuid; v_cot uuid;
begin
  select v.id into v_iva from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id where r.code='IVA' and v.version=1;
  select v.id into v_irm from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id where r.code='IRM' and v.version=1;
  select v.id into v_igf from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id where r.code='IGF' and v.version=1;
  select v.id into v_irp from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id where r.code='IRP' and v.version=1;
  select v.id into v_iba from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id where r.code='IBA' and v.version=1;
  select v.id into v_itp from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id where r.code='ITP' and v.version=1;
  select v.id into v_cot from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id where r.code='COT_TRA' and v.version=1;
  assert plone27_tax_calc(v_iva,1000)=120,        'IVA: 1.000 Pz deben dar 120 Pz (Art. T26)';
  assert plone27_tax_calc(v_irm,1000)=10,         'IRM: 1.000 Pz al 1 % deben dar 10 Pz (Art. T30)';
  assert plone27_tax_calc(v_igf,900000)=106400,   'IGF: 900.000 Pz deben dar 106.400 Pz (Art. T33)';
  assert plone27_tax_calc(v_irp,600)=5,           'IRP: 600 Pz mensuales deben dar 5 Pz (Art. T36)';
  assert plone27_tax_calc(v_iba,8000)=435,        'IBA: 8.000 Pz deben dar 435 Pz (Art. T39)';
  assert plone27_tax_calc(v_itp,75000)=4200,      'ITP: 75.000 Pz deben dar 4.200 Pz (Art. T45)';
  assert plone27_tax_calc(v_cot,1500)=112.50,     'COT: 1.500 Pz al 7,5 % deben dar 112,50 Pz (Art. 4.5)';
end $$;

-- ==================== DATOS DE LA NORMA Y CUENTAS (0012_seed_normas_T.sql) ====================
-- Placeta One · seed 0012 · Recargos T57 (Art. T57). Ejecutar después de 0011 y de su seed. Entra en BORRADOR.
-- Publicar con plone27_tax_publish (aprobador distinto del autor). Sin publicar, T57 no actúa.

insert into plone27_tax_rules(code,name,collector_account,max_rate) values
 ('RECARGO_T57','Recargo por presentación o pago fuera de plazo (Art. T57)',
  (select nullif(value,'')::uuid from plone27_config where key='cuenta_reserva'),null)
on conflict(code) do nothing;

insert into plone27_tax_rule_versions(rule_id,version,method,rate,valid_from,reason,status)
select r.id,1,'brackets',0,date '2027-01-01','Art. T57: tramo por días de retraso sobre lo pendiente (prevalece sobre Art. 4.3)','draft'
from plone27_tax_rules r where r.code='RECARGO_T57'
on conflict(rule_id,version) do nothing;

-- Tramos en días: (desde, hasta]. «hasta 7 días» = 1..7; «de 8 a 30» = 8..30; etc.
insert into plone27_tax_brackets(version_id,from_amount,to_amount,rate)
select v.id,b.f,b.t,b.r from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id
join (values (0::numeric,7::numeric,1::numeric),(7::numeric,30::numeric,3::numeric),(30::numeric,90::numeric,5::numeric),
             (90::numeric,180::numeric,10::numeric),(180::numeric,null::numeric,15::numeric)) as b(f,t,r) on true
where ru.code='RECARGO_T57' and v.version=1
on conflict do nothing;

-- Autocomprobación de los tramos del Art. T57
do $$ declare vid uuid; begin
  select v.id into vid from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id where ru.code='RECARGO_T57' and v.version=1;
  assert plone27_bracket_rate(vid,1)=1,   'T57: 1 día debe ser 1 %';
  assert plone27_bracket_rate(vid,7)=1,   'T57: 7 días debe ser 1 %';
  assert plone27_bracket_rate(vid,8)=3,   'T57: 8 días debe ser 3 %';
  assert plone27_bracket_rate(vid,30)=3,  'T57: 30 días debe ser 3 %';
  assert plone27_bracket_rate(vid,31)=5,  'T57: 31 días debe ser 5 %';
  assert plone27_bracket_rate(vid,90)=5,  'T57: 90 días debe ser 5 %';
  assert plone27_bracket_rate(vid,91)=10, 'T57: 91 días debe ser 10 %';
  assert plone27_bracket_rate(vid,181)=15,'T57: 181 días debe ser 15 %';
end $$;

-- ==================== DATOS DE LA NORMA Y CUENTAS (0013_seed_cuentas_institucionales.sql) ====================
-- Placeta One · seed 0013 · Cuentas institucionales. Ejecutar después de 0012 y de los seeds 0011 y 0012.
-- Crea la cuenta de Tributos (IBAN propia), fija el origen de la RBU y los destinos por impuesto.
-- Las cuentas institucionales quedan SIN aprobador registrado: regístralo con plone27_institutional_set (el informe lo avisa).

do $$ declare bk uuid; tr uuid; begin
  select id into bk from plone27_banks where code='0000';
  if not exists(select 1 from plone27_config where key='cuenta_tributos') then
    tr:=(plone27_open_account(bk,'system','Tributos · cuenta institucional',null,null)->>'id')::uuid;
    insert into plone27_config(key,value) values('cuenta_tributos',tr::text);
  end if;
  if not exists(select 1 from plone27_config where key='cuenta_rbu_origen') then
    insert into plone27_config(key,value) select 'cuenta_rbu_origen',value from plone27_config where key='cuenta_reserva';
  end if;
end $$;

-- Destino por defecto de los impuestos: Tributos. Las cotizaciones siguen en la Reserva (Art. 4.5).
update plone27_tax_rules set collector_account=(select nullif(value,'')::uuid from plone27_config where key='cuenta_tributos')
  where code not in('COT_EMP','COT_TRA');

-- Cuentas institucionales de partida (sin aprobador: pendiente de registrar)
insert into plone27_institutional_accounts(account_id,motivo,puede_operar_junior,aprobado_por)
select (select nullif(value,'')::uuid from plone27_config where key=v.k), v.m, v.j, null from (values
  ('cuenta_reserva','Cuenta de Reserva del Grupo: cotizaciones y fondos de la RBU',false),
  ('cuenta_tributos','Cuenta de Tributos: recaudación de los impuestos',false),
  ('cuenta_placeta_junior','Placeta Junior · pagos asumidos: pagador Junior si Capitalia no paga',true)
) as v(k,m,j)
on conflict(account_id) do nothing;

do $$ begin
  assert not exists(select 1 from plone27_tax_rules where collector_account is null), 'Todo impuesto necesita destino';
  assert (select count(*) from plone27_institutional_accounts) >= 3, 'Faltan cuentas institucionales';
end $$;

-- ===================== CIERRE: entidad Capitalia y comprobación de preparación =====================

-- Capitalia Bank: se crea en borrador (la activa la aprobación de personal). Si ya existe, no hace nada.
do $$ begin
  if not exists(select 1 from plone27_banks where name ilike 'Capitalia%') then
    perform plone27_open_bank('Capitalia Bank', null);
  end if;
end $$;

-- Vista de preparación: qué está listo, qué falta y quién debe actuar.
drop view if exists plone27_listo cascade;
create view plone27_listo as
select 1 orden,'Estructura' area,'Entidad reservada 0000' comprobacion,
  case when exists(select 1 from plone27_banks where code='0000') then 'OK' else 'FALTA' end estado,
  'Creada por la migración 0003' accion
union all select 2,'Cuentas institucionales','Cuenta de Reserva del Grupo',
  case when exists(select 1 from plone27_config where key='cuenta_reserva') then 'OK' else 'FALTA' end,'Creada por el seed 0011'
union all select 2,'Cuentas institucionales','Cuenta de Tributos (IBAN propio)',
  case when exists(select 1 from plone27_config where key='cuenta_tributos') then 'OK' else 'FALTA' end,'Creada por el seed 0013'
union all select 2,'Cuentas institucionales','Origen de la RBU configurado',
  case when exists(select 1 from plone27_config where key='cuenta_rbu_origen') then 'OK' else 'FALTA' end,'Por defecto, la Reserva'
union all select 2,'Cuentas institucionales','Cuenta de Placeta Junior (pagos asumidos)',
  case when exists(select 1 from plone27_config where key='cuenta_placeta_junior') then 'OK' else 'FALTA' end,'Creada por el seed 0011'
union all select 2,'Cuentas institucionales','Cuentas institucionales con aprobador registrado',
  case when exists(select 1 from plone27_institutional_accounts) and not exists(select 1 from plone27_institutional_accounts where aprobado_por is null) then 'OK' else 'PENDIENTE' end,
  'Registrar con plone27_institutional_set, indicando el aprobador'
union all select 3,'Impuestos','Destino de '||r.code,
  case when r.collector_account is not null then 'OK' else 'FALTA' end,'Configurar en /admin/destinos'
  from plone27_tax_rules r
union all select 4,'Normas','Norma '||r.code||' publicada',
  case when exists(select 1 from plone27_tax_rule_versions v where v.rule_id=r.id and v.status='published') then 'OK' else 'PENDIENTE' end,
  'Publicar con plone27_tax_publish (aprobador distinto del autor)'
  from plone27_tax_rules r
union all select 5,'Junior y Capitalia','Entidad Capitalia creada',
  case when exists(select 1 from plone27_banks where name ilike 'Capitalia%') then 'OK' else 'FALTA' end,'Creada en borrador por este archivo'
union all select 5,'Junior y Capitalia','Capitalia activa con cuenta principal',
  case when exists(select 1 from plone27_banks where name ilike 'Capitalia%' and status='active' and main_account is not null) then 'OK' else 'PENDIENTE' end,
  'Aprobar la entidad y abrir su cuenta principal'
union all select 5,'Junior y Capitalia','Capitalia designada como pagador Junior',
  case when exists(select 1 from plone27_config c join plone27_banks b on b.id::text=c.value where c.key='entidad_capitalia' and b.name ilike 'Capitalia%') then 'OK' else 'PENDIENTE' end,
  'plone27_set_junior_payer, cuando Capitalia esté activa'
union all select 6,'Ajustes','SMI mensual de 160 Pz',
  case when (select value#>>'{}' from plone27_settings where key='smi_mensual_completa_pz')='160' then 'OK' else 'REVISAR' end,'Instrucción de la Junta'
union all select 6,'Ajustes','Pago de impuestos Junior por Capitalia activo',
  case when (select value#>>'{}' from plone27_settings where key='capitalia_asume_impuestos_junior')='true' then 'OK' else 'REVISAR' end,'Decisión de la Junta (normativa, Art. T105)'
union all select 6,'Ajustes','Interés de demora por segundo desactivado (prevalece T57)',
  case when (select value#>>'{}' from plone27_settings where key='demora_habilitada')='false' then 'OK' else 'REVISAR' end,'Art. T100'
union all select 6,'Ajustes','Tipo de interés de cuotas aprobado',
  case when (select (value#>>'{}')::numeric from plone27_settings where key='interes_anual_pct')>0 then 'OK' else 'PENDIENTE' end,
  'Lo fija la entidad dentro del tope. La norma no lo fija'
union all select 6,'Ajustes','Tipo de demora aprobado',
  case when (select (value#>>'{}')::numeric from plone27_settings where key='demora_anual_pct')>0 then 'OK' else 'PENDIENTE' end,
  'Lo aprueba el Departamento Económico'
union all select 7,'Seguridad','Tablas sin seguridad por filas (RLS)',
  case when exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
                   where n.nspname='public' and c.relname like 'plone27\_%' and c.relkind='r' and not c.relrowsecurity) then 'REVISAR' else 'OK' end,
  'Volver a ejecutar este archivo'
union all select 7,'Seguridad','Funciones accesibles por anon o authenticated',
  case when exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.proname like 'plone27\_%'
                     and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))) then 'REVISAR' else 'OK' end,
  'Solo service_role debe ejecutar estas funciones'
union all select 7,'Seguridad','Personal con rol admin activo',
  case when exists(select 1 from plone27_staff where role='admin') then 'OK' else 'PENDIENTE' end,
  'Crear el usuario en Auth y dar de alta su rol en plone27_staff'
union all select 8,'Certificación','Informe de certificación',
  case when (plone27_certification_report()->>'estado')='OK' then 'OK' else 'REVISAR' end,'Ver /admin/infraestructura'
union all select 9,'Operación','Variables de entorno en Vercel (CRON_SECRET, claves de Supabase)','MANUAL','Ver .env.example'
union all select 9,'Operación','Cron diario /api/cron/finanzas activo','MANUAL','Ver vercel.json';

revoke all on plone27_listo from anon, authenticated;
grant select on plone27_listo to service_role;

do $$ begin
  raise notice 'Instalación completa. Comprobaciones: % en total, % no OK (ver plone27_listo).',
    (select count(*) from plone27_listo), (select count(*) from plone27_listo where estado<>'OK');
end $$;

commit;
