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
create or replace function plone27_rv_guard() returns trigger language plpgsql as $$ begin
  if old.status='published' then raise exception 'Versión publicada inmutable; crea una nueva'; end if;
  if new.status='published' and (new.approver is null or new.approver is not distinct from new.author and false) then raise exception 'Requiere aprobador'; end if;
  return new; end $$;
drop trigger if exists t_rv_guard on plone27_tax_rule_versions;
create trigger t_rv_guard before update on plone27_tax_rule_versions for each row execute function plone27_rv_guard();

-- Saldo derivado: créditos − débitos − reservas activas
create or replace view plone27_account_balances with(security_invoker=true) as
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
language plpgsql security definer set search_path=public as $$ begin
  if p_from=p_to or p_amount<=0 then raise exception 'Transferencia inválida'; end if;
  return plone27_post(p_key,'transfer',p_memo,jsonb_build_array(
    jsonb_build_object('account',p_from,'dir','debit','amount',p_amount),
    jsonb_build_object('account',p_to,'dir','credit','amount',p_amount)),p_actor);
end $$;

create or replace function plone27_reverse(p_key text,p_tx uuid,p_reason text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$ declare r uuid; lines jsonb; begin
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
create or replace function plone27_bank_guard() returns trigger language plpgsql as $$ begin
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
create or replace function plone27_rv_cap() returns trigger language plpgsql as $$ declare m numeric; begin
 select max_rate into m from plone27_tax_rules where id=new.rule_id;
 if (new.scope_bank is not null or new.scope_op is not null) and m is not null and new.method='percent' and new.rate>m then raise exception 'Regla específica supera el límite central (%)',m; end if; return new; end $$;
drop trigger if exists t_rv_cap on plone27_tax_rule_versions;
create trigger t_rv_cap before insert or update on plone27_tax_rule_versions for each row execute function plone27_rv_cap();
create table if not exists plone27_tax_exemptions(id uuid primary key default gen_random_uuid(), rule_id uuid references plone27_tax_rules, account_id uuid references plone27_accounts,
 valid_from date not null, valid_to date, reason text not null, legal_basis text not null, approved_by uuid not null);
create table if not exists plone27_tax_distribution(id uuid primary key default gen_random_uuid(), rule_id uuid not null references plone27_tax_rules, account_id uuid not null references plone27_accounts,
 pct numeric(5,2) not null check(pct>0 and pct<=100), approved_by uuid);
create or replace function plone27_dist_guard() returns trigger language plpgsql as $$ begin
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
create or replace function plone27_design_step(p_design uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare o text; begin
 select status into o from plone27_card_designs where id=p_design for update;
 if (o,p_to) not in(('draft','submitted'),('submitted','review'),('review','approved'),('review','rejected'),('rejected','draft')) then raise exception 'Transición no permitida'; end if;
 update plone27_card_designs set status=p_to where id=p_design; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'design_step','design',p_design::text,to_jsonb(p_to)); end $$;
create or replace function plone27_design_buy(p_key text,p_design uuid,p_account uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare d plone27_card_designs; tx uuid; t numeric; begin
 select * into d from plone27_card_designs where id=p_design; if d.status<>'approved' then raise exception 'Diseño no aprobado'; end if;
 t:=d.price+d.license_fee; if t>0 then tx:=plone27_transfer(p_key,p_account,d.revenue_account,t,'Diseño '||d.name,p_actor); end if;
 insert into plone27_design_purchases values(p_design,p_account,tx) on conflict do nothing; return tx; end $$;
create or replace function plone27_card_authorize(p_card uuid,p_amount numeric,p_merchant uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare c plone27_cards; res uuid; ch uuid; begin
 select * into c from plone27_cards where id=p_card for update; if c.status<>'active' then raise exception 'Tarjeta no activa'; end if;
 if c.kind='credit' then
  if coalesce((select sum(amount) from plone27_card_charges where card_id=p_card and status in('authorized','billed')),0)+p_amount>coalesce(c.credit_limit,0) then raise exception 'Límite de crédito superado'; end if;
 else if plone27_available(c.account_id)<p_amount then raise exception 'Saldo insuficiente'; end if;
  insert into plone27_reservations(account_id,amount,reason) values(c.account_id,p_amount,'card auth') returning id into res; end if;
 insert into plone27_card_charges(card_id,merchant_account,amount,reservation_id) values(p_card,p_merchant,p_amount,res) returning id into ch; return ch; end $$;
create or replace function plone27_card_settle(p_key text,p_charge uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare ch plone27_card_charges; c plone27_cards; tx uuid; begin
 select * into ch from plone27_card_charges where id=p_charge for update; if ch.status<>'authorized' then raise exception 'Cargo ya procesado'; end if;
 select * into c from plone27_cards where id=ch.card_id;
 if c.kind='credit' then update plone27_card_charges set status='billed' where id=p_charge; return null; end if;  -- crédito: consumo ≠ liquidación
 update plone27_reservations set status='released' where id=ch.reservation_id;
 tx:=plone27_transfer(p_key,c.account_id,ch.merchant_account,ch.amount,'Tarjeta',p_actor); update plone27_card_charges set status='settled' where id=p_charge; return tx; end $$;
create or replace function plone27_card_close_cycle(p_key text,p_card uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
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
create or replace function plone27_run_scheduled(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare s record; n int:=0; begin
 for s in select * from plone27_scheduled where status='active' and run_at<=now() order by run_at for update skip locked loop
  begin perform plone27_transfer_fee('sch:'||s.id||':'||s.run_at,s.from_account,s.to_account,s.amount,s.memo,p_actor); n:=n+1;
   if s.recurrence is null then update plone27_scheduled set status='done' where id=s.id; else update plone27_scheduled set run_at=run_at+recurrence where id=s.id; end if;
  exception when others then insert into plone27_incidents(kind,detail) values('scheduled_failed',jsonb_build_object('id',s.id,'err',sqlerrm)); end;
 end loop; return n; end $$;

-- SUBVENCIONES Y BONOS
alter table plone27_grant_programs add column if not exists funding_account uuid references plone27_accounts;
alter table plone27_justifications drop constraint plone27_justifications_status_check, add check(status in('pending','approved','paid','rejected'));
create or replace function plone27_justify(p_grant uuid,p_tx uuid,p_invoice text,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare g plone27_grants; spent numeric; jid uuid; begin
 select * into g from plone27_grants where id=p_grant for update;
 select sum(e.amount) into spent from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.transaction_id=p_tx and e.account_id=g.beneficiary_account and e.direction='debit' and t.status='posted';
 if coalesce(spent,0)<p_amount then raise exception 'Transacción no elegible o importe excesivo'; end if;
 if coalesce((select sum(amount) from plone27_justifications where grant_id=p_grant and status<>'rejected'),0)+p_amount>g.granted then raise exception 'Supera lo concedido'; end if;
 insert into plone27_justifications(grant_id,transaction_id,invoice_ref,amount) values(p_grant,p_tx,p_invoice,p_amount) returning plone27_justifications.id into jid; return jid; end $$;  -- unique(transaction_id/invoice) impide justificar dos veces
create or replace function plone27_reimburse(p_key text,p_just uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
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

create or replace function plone27_next_num(p_kind text,p_scope text,p_max bigint) returns bigint language plpgsql security definer set search_path=public as $$ declare n bigint; begin
 insert into plone27_counters values(p_kind,p_scope,1) on conflict(kind,scope) do update set last=plone27_counters.last+1 returning last into n;
 if n>p_max then raise exception 'Capacidad agotada (% / %)',p_kind,p_scope; end if; return n; end $$;
create or replace function plone27_next_id(p_kind text) returns text language plpgsql security definer set search_path=public as $$ declare f plone27_numbering_formats; sc text; n bigint; id text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and status='published' and valid_from<=current_date order by version desc limit 1;
 if not found then raise exception 'Formato % sin publicar',p_kind; end if;
 sc:=case when f.year_scoped then extract(year from current_date)::text else 'global' end;
 n:=plone27_next_num(p_kind||':v'||f.version,sc,(power(10,f.width)-1)::bigint);
 id:=f.prefix||case when f.year_scoped then sc||'-' else '' end||lpad(n::text,f.width,'0');
 insert into plone27_issued_ids(identifier,kind) values(id,p_kind); return id; end $$;

-- Configuración versionada: propuesta → simulación → publicación aprobada (no altera identificadores históricos)
create or replace function plone27_numbering_propose(p_kind text,p_prefix text,p_year boolean,p_width int,p_reason text,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare v int; begin
 select coalesce(max(version),0)+1 into v from plone27_numbering_formats where kind=p_kind;
 insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,reason,author) values(p_kind,v,p_prefix,p_year,p_width,p_reason,p_actor); return v; end $$;
create or replace function plone27_numbering_simulate(p_kind text,p_version int,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare f plone27_numbering_formats; s text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and version=p_version;
 s:=f.prefix||case when f.year_scoped then extract(year from current_date)||'-' else '' end||lpad('1',f.width,'0');
 return jsonb_build_object('sample',s,'collides',exists(select 1 from plone27_issued_ids where identifier=s),'capacity',power(10,f.width)-1); end $$;
create or replace function plone27_numbering_publish(p_kind text,p_version int,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 if plone27_numbering_simulate(p_kind,p_version,p_actor)->>'collides'='true' then raise exception 'Colisión de formato'; end if;
 update plone27_numbering_formats set status='published',approved_by=p_actor,valid_from=current_date where kind=p_kind and version=p_version and status='draft';
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'numbering_publish',p_kind,p_version::text); end $$;

-- Referencias automáticas e inmutables en documentos
create or replace function plone27_set_ref() returns trigger language plpgsql security definer set search_path=public as $$ declare k text:=tg_argv[0]; begin
 if tg_table_name='plone27_grants' then select case p.kind when 'bono' then 'BON' else 'SUB' end into k from plone27_grant_programs p where p.id=new.program_id; end if;
 if new.ref is null then new.ref:=plone27_next_id(k); end if; return new; end $$;
create or replace function plone27_ref_lock() returns trigger language plpgsql as $$ begin
 if new.ref is distinct from old.ref then raise exception 'Referencia inmutable'; end if; return new; end $$;
do $$ declare x text[]; begin
 foreach x slice 1 in array array[['plone27_tax_receipts','REC'],['plone27_tax_adjustments','REG'],['plone27_grants','SUB'],['plone27_justifications','JUS'],['plone27_incidents','INC'],['plone27_debts','DEU'],['plone27_approvals','AUT']] loop
  execute format('alter table %I add column if not exists ref text unique',x[1]);
  execute format('drop trigger if exists t_ref on %I',x[1]); execute format('create trigger t_ref before insert on %I for each row execute function plone27_set_ref(%L)',x[1],x[2]);
  execute format('drop trigger if exists t_ref_lock on %I',x[1]); execute format('create trigger t_ref_lock before update on %I for each row execute function plone27_ref_lock()',x[1]); end loop; end $$;
alter table plone27_transactions add column if not exists ref text unique, add column if not exists transfer_ref text unique;
create or replace function plone27_tx_refs() returns trigger language plpgsql security definer set search_path=public as $$ begin
 new.ref:=plone27_next_id('OPE'); if new.kind='transfer' then new.transfer_ref:=plone27_next_id('TRF'); end if; return new; end $$;
drop trigger if exists t_tx_refs on plone27_transactions;
create trigger t_tx_refs before insert on plone27_transactions for each row execute function plone27_tx_refs();
drop trigger if exists t_tx_ref_lock on plone27_transactions;
create trigger t_tx_ref_lock before update on plone27_transactions for each row execute function plone27_ref_lock();
alter table plone27_justifications add column if not exists reimb_ref text unique;
create or replace function plone27_reimb_ref() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.status='paid' and new.reimb_ref is null then new.reimb_ref:=plone27_next_id('REE'); end if; return new; end $$;
drop trigger if exists t_reimb on plone27_justifications;
create trigger t_reimb before update on plone27_justifications for each row execute function plone27_reimb_ref();

-- Entidades y cuentas PZ-EEEE-CCCC (servidor únicamente, inmutables)
do $$ begin alter table plone27_banks add constraint banks_code4 check(code ~ '^[0-9]{4}$') not valid; exception when duplicate_object then null; end $$;
insert into plone27_banks(code,name,status) values('0000','Placeta Administración','active')
on conflict do nothing;   -- entidad reservada (cuentas de sistema)
alter table plone27_accounts add column if not exists iban text unique;
create or replace function plone27_iban_guard() returns trigger language plpgsql as $$ begin
 if tg_op='INSERT' then
  if new.iban is null or new.iban !~ '^PZ-[0-9]{4}-[0-9]{4}$' or substr(new.iban,4,4) is distinct from (select code from plone27_banks where id=new.bank_id) then raise exception 'IBAN solo generado por servidor'; end if;
 elsif new.iban is distinct from old.iban or new.bank_id is distinct from old.bank_id then raise exception 'IBAN inmutable'; end if; return new; end $$;
drop trigger if exists t_iban on plone27_accounts;
create trigger t_iban before insert or update on plone27_accounts for each row execute function plone27_iban_guard();
create or replace function plone27_open_bank(p_name text,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare c text; id uuid; begin
 c:=lpad(plone27_next_num('BANK','global',9999)::text,4,'0'); insert into plone27_banks(code,name) values(c,p_name) returning plone27_banks.id into id; return jsonb_build_object('id',id,'code',c); end $$;
create or replace function plone27_open_account(p_bank uuid,p_kind text,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare vc text; i text; id uuid; begin
 select b.code into vc from plone27_banks b where b.id=p_bank and b.status='active'; if vc is null then raise exception 'Entidad inexistente o no activa'; end if;
 i:='PZ-'||vc||'-'||lpad(plone27_next_num('ACC',vc,9999)::text,4,'0');
 insert into plone27_accounts(bank_id,kind,name,owner_user,iban,allow_negative) values(p_bank,p_kind,p_name,p_owner,i,p_kind='system') returning plone27_accounts.id into id;
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'open_account','account',i); return jsonb_build_object('id',id,'iban',i); end $$;

-- Tarjetas: id administrativo PL27-TAR; número visible solo en pruebas; sin PAN/CVV almacenados
alter table plone27_cards drop constraint plone27_cards_status_check, add check(status in('active','suspended','blocked','closed')),
 add column if not exists card_ref text unique, add column if not exists is_test boolean not null default false, add column if not exists expires date, add column if not exists last4 text, add column if not exists pan_hash text unique;
create or replace function plone27_issue_card(p_account uuid,p_kind text,p_design uuid,p_limit numeric,p_test boolean,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare r text; num text; cid uuid; begin
 if not exists(select 1 from plone27_accounts where id=p_account and status='active') then raise exception 'Cuenta no activa'; end if;
 if p_design is not null and not exists(select 1 from plone27_design_purchases where design_id=p_design and account_id=p_account) then raise exception 'Diseño no adquirido'; end if;
 r:=plone27_next_id('TAR');
 if p_test then num:=lpad(floor(random()*10000000000000000)::bigint::text,16,'0'); end if;
 insert into plone27_cards(account_id,kind,design_id,credit_limit,card_ref,is_test,expires,last4,pan_hash)
  values(p_account,p_kind,p_design,p_limit,r,p_test,current_date+interval '5 years',right(num,4),encode(sha256(convert_to(coalesce(num,r),'utf8')),'hex')) returning plone27_cards.id into cid;
 return jsonb_build_object('id',cid,'card_ref',r,'test_number',regexp_replace(num,'(\d{4})(?=\d)','\1 ','g')); end $$;  -- el número de prueba se devuelve una sola vez
create or replace function plone27_card_set_status(p_card uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare o text; begin
 select status into o from plone27_cards where id=p_card for update; if o='closed' then raise exception 'Tarjeta cancelada'; end if;
 update plone27_cards set status=p_to where id=p_card; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'card_status','card',p_card::text,to_jsonb(p_to)); end $$;
create or replace function plone27_card_renew(p_card uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare c plone27_cards; begin
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
create or replace function plone27_staff_set(p_user uuid,p_role text,p_active boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 insert into plone27_staff(user_id,role,active) values(p_user,p_role,p_active) on conflict(user_id) do update set role=p_role,active=p_active;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'staff_set','staff',p_user::text,jsonb_build_object('role',p_role,'active',p_active)); end $$;

-- Lotes y nóminas (cada elemento idempotente y aislado: uno fallido no bloquea el resto)
create table if not exists plone27_batches(id uuid primary key default gen_random_uuid(), kind text not null check(kind in('payroll','batch')), from_account uuid not null references plone27_accounts, status text not null default 'open' check(status in('open','done','partial')));
create table if not exists plone27_batch_items(id uuid primary key default gen_random_uuid(), batch_id uuid not null references plone27_batches, to_account uuid not null references plone27_accounts,
 amount numeric(18,2) not null check(amount>0), status text not null default 'pending' check(status in('pending','paid','failed')), error text);
create or replace function plone27_run_batch(p_batch uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
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
create or replace function plone27_settle_bank(p_bank uuid,p_from date,p_to date,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare sid uuid; begin
 select id into sid from plone27_settlements where bank_id=p_bank and period_from=p_from and period_to=p_to; if sid is not null then return sid; end if;
 insert into plone27_settlements(bank_id,period_from,period_to,evaluated,collected,pending,refunded)
  select p_bank,p_from,p_to,coalesce(sum(r.amount),0),coalesce(sum(r.amount) filter(where r.status='paid'),0),coalesce(sum(r.amount) filter(where r.status='issued'),0),coalesce(sum(r.refunded),0)
  from plone27_tax_receipts r join plone27_accounts a on a.id=r.account_id where a.bank_id=p_bank and r.created_at::date between p_from and p_to returning plone27_settlements.id into sid; return sid; end $$;

-- Deuda con origen autorizado
alter table plone27_debts add column if not exists creditor_account uuid references plone27_accounts;
create or replace function plone27_debt_pay(p_key text,p_debt uuid,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare d plone27_debts; tx uuid; begin
 select * into d from plone27_debts where id=p_debt for update; if d.disputed then raise exception 'Deuda en disputa: no se cobra'; end if;
 if d.paid+p_amount>d.principal+d.authorized_charges then raise exception 'Excede la deuda'; end if;
 tx:=plone27_transfer(p_key,d.account_id,d.creditor_account,p_amount,'Deuda '||d.ref,p_actor); update plone27_debts set paid=paid+p_amount where id=p_debt; return tx; end $$;

-- Tarjetas físicas: pedido → producción → envío → activación (suspendida hasta activar)
create table if not exists plone27_card_orders(id uuid primary key default gen_random_uuid(), card_id uuid not null unique references plone27_cards, status text not null default 'ordered' check(status in('ordered','produced','shipped','activated','cancelled')), updated_at timestamptz default now());
create or replace function plone27_card_order_step(p_card uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare o text; begin
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
create or replace view plone27_account_balances with(security_invoker=true) as
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
alter table plone27_tax_rule_versions drop constraint plone27_tax_rule_versions_method_check, add check(method in('percent','fixed','brackets'));
create table if not exists plone27_tax_brackets(version_id uuid not null references plone27_tax_rule_versions, from_amount numeric(18,2) not null, to_amount numeric(18,2), rate numeric(9,4) not null, primary key(version_id,from_amount));
create or replace function plone27_tax_calc(p_version uuid,p_base numeric) returns numeric language sql stable as $$
 select round(least(coalesce(v.max_amount,'infinity'),greatest(coalesce(v.min_amount,0),
  case v.method when 'percent' then p_base*v.rate/100 when 'fixed' then v.rate
   else coalesce((select sum((least(p_base,coalesce(b.to_amount,'infinity'))-b.from_amount)*b.rate/100) from plone27_tax_brackets b where b.version_id=v.id and p_base>b.from_amount),0) end)),2)
 from plone27_tax_rule_versions v where v.id=p_version $$;
alter table plone27_tax_receipts drop constraint plone27_tax_receipts_status_check, add check(status in('issued','partial','paid','rectified')), add column if not exists paid_amount numeric(18,2) not null default 0;
create or replace function plone27_tax_pay_partial(p_key text,p_receipt uuid,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
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
create or replace function plone27_emit() returns trigger language plpgsql security definer set search_path=public as $$ declare b uuid[]; p jsonb; begin
 if new.action='post' then
  select array_agg(distinct a.bank_id) into b from plone27_accounts a where a.id in(select (x->>'account')::uuid from jsonb_array_elements(new.detail) x);
  select jsonb_build_object('operation',t.ref,'transfer',t.transfer_ref,'kind',t.kind) into p from plone27_transactions t where t.id=new.entity_id::uuid;
  insert into plone27_outbox(event,bank_ids,payload) values('transaction.posted',coalesce(b,'{}'),p); end if; return new; end $$;
drop trigger if exists t_emit on plone27_audit_log;
create trigger t_emit after insert on plone27_audit_log for each row execute function plone27_emit();
create or replace view plone27_alerts with(security_invoker=true) as
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
create or replace function plone27_setting(p_key text,p_bank uuid default null) returns jsonb language plpgsql stable security definer set search_path=public as $$ declare v jsonb; begin
 select coalesce((select b.value from plone27_bank_settings b where b.bank_id=p_bank and b.key=p_key),s.value) into v from plone27_settings s where s.key=p_key;
 if v is null then raise exception 'Ajuste desconocido: %',p_key; end if; return v; end $$;
create or replace function plone27_setting_validate(p_key text,p_value jsonb) returns void language plpgsql stable as $$ declare s plone27_settings; begin
 select * into s from plone27_settings where key=p_key; if s.key is null then raise exception 'Ajuste desconocido'; end if;
 if s.vtype='number' then if jsonb_typeof(p_value)<>'number' or (p_value#>>'{}')::numeric<coalesce(s.min_v,-1e18) or (p_value#>>'{}')::numeric>coalesce(s.max_v,1e18) then raise exception 'Fuera de los límites centrales [% , %]',s.min_v,s.max_v; end if;
 elsif s.vtype='boolean' then if jsonb_typeof(p_value)<>'boolean' then raise exception 'Se esperaba booleano'; end if;
 elsif s.vtype='enum' then if not (p_value#>>'{}')=any(s.allowed) then raise exception 'Valor no permitido (%)',s.allowed; end if;
 elsif jsonb_typeof(p_value)<>'string' then raise exception 'Se esperaba texto'; end if; end $$;
create or replace function plone27_setting_apply(p_change uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare c plone27_setting_changes; begin
 select * into c from plone27_setting_changes where id=p_change and status='pending' for update; if c.id is null then return; end if;
 if c.bank_id is null then update plone27_settings set value=c.new_value,version=version+1,updated_at=now() where key=c.key;
 else insert into plone27_bank_settings values(c.bank_id,c.key,c.new_value) on conflict(bank_id,key) do update set value=c.new_value; end if;
 update plone27_setting_changes set status='applied',approved_by=coalesce(approved_by,p_actor) where id=p_change;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'setting_applied','setting',c.key,jsonb_build_object('bank',c.bank_id,'new',c.new_value)); end $$;
create or replace function plone27_setting_propose(p_key text,p_value jsonb,p_bank uuid,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare s plone27_settings; id uuid; begin
 select * into s from plone27_settings where key=p_key; perform plone27_setting_validate(p_key,p_value);
 if p_bank is not null and not s.bank_overridable then raise exception 'Este ajuste solo es central'; end if; if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 insert into plone27_setting_changes(key,bank_id,new_value,old_value,reason,proposed_by) values(p_key,p_bank,p_value,plone27_setting(p_key,p_bank),p_reason,p_actor) returning plone27_setting_changes.id into id;
 if not s.sensitive then perform plone27_setting_apply(id,p_actor); end if; return id; end $$;
create or replace function plone27_setting_approve(p_change uuid,p_approve boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare c plone27_setting_changes; begin
 select * into c from plone27_setting_changes where id=p_change and status='pending'; if c.id is null then raise exception 'Cambio no pendiente'; end if;
 if c.proposed_by is not distinct from p_actor then raise exception 'El proponente no puede aprobar su propio cambio'; end if;
 if p_approve then update plone27_setting_changes set approved_by=p_actor where id=p_change; perform plone27_setting_apply(p_change,p_actor);
 else update plone27_setting_changes set status='rejected',approved_by=p_actor where id=p_change; end if; end $$;

-- Lo que antes estaba fijado en el código ahora lee la configuración
create or replace function plone27_adjust_approve(p_adj uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare a plone27_tax_adjustments; begin
 select * into a from plone27_tax_adjustments where id=p_adj for update;
 if a.created_by is not distinct from p_actor and abs(a.diff)>=(plone27_setting('dual_approval_threshold')#>>'{}')::numeric then raise exception 'Doble aprobación: debe aprobar otra persona'; end if;
 update plone27_tax_adjustments set status='approved',approved_by=p_actor where id=p_adj and status='simulated'; end $$;
create or replace function plone27_ledger_limits() returns trigger language plpgsql security definer set search_path=public as $$
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
create or replace function plone27_product_guard() returns trigger language plpgsql as $$ begin
 if new.status is distinct from old.status then
  if (old.status,new.status) not in(('draft','active'),('active','retired'),('draft','retired')) then raise exception 'Transición de producto % → % no permitida',old.status,new.status; end if;
  if new.status='active' and new.approved_by is null then raise exception 'Activar un producto requiere aprobación registrada'; end if; end if; return new; end $$;
drop trigger if exists t_product_guard on plone27_products;
create trigger t_product_guard before update on plone27_products for each row execute function plone27_product_guard();
create or replace function plone27_open_account_p(p_product uuid,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare p plone27_products; k text; r jsonb; begin
 select * into p from plone27_products where id=p_product and status='active' and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
 if p.id is null then raise exception 'Producto no disponible'; end if; if p.kind not like 'account\_%' then raise exception 'No es un producto de cuenta'; end if;
 k:=case p.kind when 'account_personal' then 'personal' when 'account_business' then 'business' when 'account_shared' then 'shared' else 'junior' end;
 r:=plone27_open_account(p.bank_id,k,p_name,p_owner,p_actor);
 update plone27_accounts set product_id=p_product,daily_limit=coalesce(p.daily_limit,daily_limit) where id=(r->>'id')::uuid; return r; end $$;
create or replace function plone27_charge_product_fees(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare n int:=0; a record; begin
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
language plpgsql security definer set search_path=public as $$ begin
 if not exists(select 1 from plone27_account_members where account_id=p_from and user_id=p_user) and not exists(select 1 from plone27_juniors where account_id=p_from and guardian_user=p_user)
  then raise exception 'El usuario no está autorizado en la cuenta de origen'; end if;
 return plone27_transfer_fee(p_key,p_from,p_to,p_amount,p_memo,p_actor); end $$;

-- Reservas manuales (programadas, retenciones)
create or replace function plone27_reserve(p_account uuid,p_amount numeric,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare rid uuid; begin
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
declare p plone27_products; k text; r jsonb; begin
 select * into p from plone27_products where id=p_product and status='active' and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
 if p.id is null then raise exception 'Producto no disponible'; end if;
 if p.kind not like 'account\_%' and p.kind<>'internal_credit' then raise exception 'No es un producto de cuenta'; end if;
 k:=case p.kind when 'account_business' then 'business' when 'account_shared' then 'shared' when 'account_junior' then 'junior' else 'personal' end;
 r:=plone27_open_account(p.bank_id,k,p_name,p_owner,p_actor);
 update plone27_accounts set product_id=p_product,daily_limit=coalesce(p.daily_limit,daily_limit),allow_negative=(p.kind='internal_credit'),credit_limit=case when p.kind='internal_credit' then coalesce(p.credit_limit,0) else 0 end where id=(r->>'id')::uuid; return r; end $$;
create or replace function plone27_accrue_interest(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare n int:=0; a record; i numeric; begin
 for a in select ac.id,p.interest_rate r,p.fee_account fa,b.booked from plone27_accounts ac join plone27_products p on p.id=ac.product_id join plone27_account_balances b on b.account_id=ac.id
  where p.kind='internal_credit' and p.interest_rate>0 and p.fee_account is not null and ac.status='active' and b.booked<0 loop
  i:=round(-a.booked*a.r/100/12,2);
  if i>0 then begin perform plone27_post('int:'||a.id||':'||to_char(now(),'YYYY-MM'),'interest','Interés mensual',jsonb_build_array(jsonb_build_object('account',a.id,'dir','debit','amount',i),jsonb_build_object('account',a.fa,'dir','credit','amount',i)),p_actor); n:=n+1;
   exception when others then insert into plone27_incidents(kind,detail) values('interest_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end; end if; end loop; return n; end $$;

-- Reversos coherentes y recibos
create or replace function plone27_on_reversed() returns trigger language plpgsql as $$ begin
 if new.status='reversed' and old.status<>'reversed' then
  if new.kind='reversal' then raise exception 'No se puede revertir una reversión'; end if;
  update plone27_tax_receipts r set paid_amount=greatest(r.paid_amount-d.s,0),paid_tx=null,status=case when r.paid_amount-d.s>0 then 'partial' else 'issued' end
   from (select coalesce(sum(amount),0) s from plone27_ledger_entries where transaction_id=new.id and direction='debit') d where r.paid_tx=new.id; end if; return new; end $$;
drop trigger if exists t_on_reversed on plone27_transactions;
create trigger t_on_reversed before update on plone27_transactions for each row execute function plone27_on_reversed();
create or replace function plone27_receipt_paid() returns trigger language plpgsql as $$ begin
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
create or replace function plone27_policy_guard() returns trigger language plpgsql as $$ declare p jsonb:=new.params; begin
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
create or replace function plone27_debt_terms() returns trigger language plpgsql security definer set search_path=public as $$ declare pol jsonb; begin
 if new.account_id is null then return new; end if; pol:=plone27_policy_resolve('debt_terms',new.account_id); if pol is null then return new; end if;
 if tg_op='INSERT' and pol->>'max_principal' is not null and new.principal>(pol->>'max_principal')::numeric then raise exception 'Supera el principal máximo de la norma (%)',pol->>'max_principal'; end if;
 if tg_op='UPDATE' and new.paid>old.paid and pol->>'allow_partial'='false' and new.paid<new.principal+new.authorized_charges then raise exception 'La norma no permite pagos parciales'; end if; return new; end $$;
drop trigger if exists t_debt_terms on plone27_debts;
create trigger t_debt_terms before insert or update on plone27_debts for each row execute function plone27_debt_terms();
-- Recargos por mora: solo con norma publicada aplicable; se crean como deuda con origen autorizado y una sola vez por recibo
create or replace function plone27_apply_late_penalties(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
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
create or replace function plone27_dispute_open(p_type text,p_subject uuid,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare acc uuid; pol jsonb; did uuid; begin
 if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 if p_type='receipt' then select account_id into acc from plone27_tax_receipts where id=p_subject; else select account_id into acc from plone27_debts where id=p_subject; end if;
 if acc is null then raise exception 'Objeto inexistente'; end if;
 pol:=plone27_policy_resolve('dispute',acc);
 insert into plone27_disputes(subject_type,subject_id,account_id,reason,opened_by,due_at) values(p_type,p_subject,acc,p_reason,p_actor,now()+make_interval(days=>coalesce((pol->>'max_days')::int,30))) returning plone27_disputes.id into did;
 if p_type='receipt' then update plone27_tax_receipts set disputed=true where id=p_subject; else update plone27_debts set disputed=true where id=p_subject; end if; return did; end $$;
create or replace function plone27_dispute_resolve(p_id uuid,p_outcome text,p_note text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare d plone27_disputes; begin
 if p_outcome not in('upheld','rejected','withdrawn') then raise exception 'Resultado no válido'; end if;
 select * into d from plone27_disputes where id=p_id and status='open' for update; if d.id is null then raise exception 'Disputa no abierta'; end if;
 if p_outcome<>'withdrawn' and d.opened_by is not distinct from p_actor then raise exception 'La disputa debe resolverla otra persona'; end if;
 if d.subject_type='receipt' then update plone27_tax_receipts set disputed=false,status=case when p_outcome='upheld' then 'rectified' else status end where id=d.subject_id;
 else update plone27_debts set disputed=false,authorized_charges=case when p_outcome='upheld' then 0 else authorized_charges end,principal=case when p_outcome='upheld' then paid else principal end where id=d.subject_id; end if;
 update plone27_disputes set status=p_outcome,resolution=p_note,resolved_by=p_actor,resolved_at=now() where id=p_id;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'dispute_resolved','dispute',p_id::text,jsonb_build_object('outcome',p_outcome)); end $$;
create or replace view plone27_alerts with(security_invoker=true) as
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
do $$ begin alter table plone27_products add constraint products_junior_compat check(kind<>'account_junior' or (coalesce(credit_limit,0)=0 and interest_rate=0 and requires_guardian)); exception when duplicate_object then null; end $$;
create or replace function plone27_account_compat() returns trigger language plpgsql as $$ begin
 if new.kind='junior' and (new.allow_negative or new.credit_limit>0) then raise exception 'Una cuenta Junior no admite descubierto ni crédito'; end if; return new; end $$;
drop trigger if exists t_account_compat on plone27_accounts;
create trigger t_account_compat before insert or update on plone27_accounts for each row execute function plone27_account_compat();
create or replace function plone27_card_compat() returns trigger language plpgsql security definer set search_path=public as $$ declare a plone27_accounts; j plone27_junior_profiles; begin
 select * into a from plone27_accounts where id=new.account_id; if a.kind<>'junior' then return new; end if;
 if new.kind='credit' then raise exception 'Una cuenta Junior no admite tarjeta de crédito'; end if;
 select * into j from plone27_junior_profiles where customer_id=a.customer_id; if j.customer_id is not null and not j.card_enabled then raise exception 'El control parental no permite tarjetas'; end if; return new; end $$;
drop trigger if exists t_card_compat on plone27_cards;
create trigger t_card_compat before insert on plone27_cards for each row execute function plone27_card_compat();
-- Membresía mensual (renovable por la app mediante API)
create table if not exists plone27_subscriptions(id uuid primary key default gen_random_uuid(), account_id uuid unique not null references plone27_accounts, product_id uuid references plone27_products,
 status text not null default 'past_due' check(status in('active','past_due','expired','cancelled')), period_start date, period_end date not null default current_date, auto_renew boolean not null default true,
 renewals int not null default 0, last_tx uuid references plone27_transactions, created_at timestamptz default now());
create or replace function plone27_sub_create() returns trigger language plpgsql as $$ begin
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
declare s record; r jsonb; ren int:=0; exp int:=0; g int:=(plone27_setting('junior_membership_grace_days')#>>'{}')::int; begin
 for s in select * from plone27_subscriptions where status in('active','past_due') and period_end<=current_date loop
  if s.auto_renew then r:=plone27_subscription_renew(s.account_id,null,p_actor); if (r->>'renewed')='true' then ren:=ren+1; continue; end if; end if;
  if s.period_end+g<current_date then update plone27_subscriptions set status='expired' where id=s.id; exp:=exp+1; else update plone27_subscriptions set status='past_due' where id=s.id and status='active'; end if; end loop;
 return jsonb_build_object('renewed',ren,'expired',exp); end $$;
-- Reglas Junior en el libro: control parental heredado de la ficha + membresía vigente + sin cuentas habituales
create or replace function plone27_junior_profile() returns trigger language plpgsql security definer set search_path=public as $$
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
create or replace function plone27_junior_counterparty() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if exists(select 1 from (select distinct n.transaction_id from new_rows n join plone27_transactions t on t.id=n.transaction_id where t.kind<>'reversal') x
  where exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind='junior')
   and exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind in('personal','shared','business')))
 then raise exception 'Cuenta Junior: no puede enviar ni recibir de cuentas de clientes habituales'; end if; return null; end $$;
drop trigger if exists t_junior_cp on plone27_ledger_entries;
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

create or replace function plone27_bank_accounts_guard() returns trigger language plpgsql as $$ begin
  if new.main_account is not null and not exists(select 1 from plone27_accounts a where a.id=new.main_account and a.bank_id=new.id)
    then raise exception 'La cuenta principal debe pertenecer a la propia entidad'; end if;
  if new.tax_account is not null and not exists(select 1 from plone27_accounts a where a.id=new.tax_account and a.bank_id=new.id)
    then raise exception 'La cuenta de impuestos debe pertenecer a la propia entidad'; end if;
  return new; end $$;
drop trigger if exists t_bank_accounts on plone27_banks;
drop trigger if exists t_bank_accounts on plone27_banks;
create trigger t_bank_accounts before insert or update on plone27_banks for each row execute function plone27_bank_accounts_guard();

create or replace function plone27_bank_set_accounts(p_bank uuid,p_main uuid,p_tax uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
  update plone27_banks set main_account=p_main,tax_account=p_tax where id=p_bank;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'bank_accounts','bank',p_bank::text,jsonb_build_object('main',p_main,'tax',p_tax));
end $$;

create or replace function plone27_main_account(p_bank uuid) returns uuid language plpgsql stable security definer set search_path=public as $$
declare acc uuid; begin
  select main_account into acc from plone27_banks where id=p_bank;
  if acc is null then raise exception 'La entidad no tiene cuenta principal configurada'; end if; return acc; end $$;

create or replace function plone27_reserve_account() returns uuid language plpgsql stable security definer set search_path=public as $$
declare acc uuid; begin
  select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_reserva';
  if acc is null then raise exception 'Falta la Cuenta de Reserva del Grupo (ejecuta el seed 0011)'; end if; return acc; end $$;

create or replace function plone27_collectable(p_account uuid,p_amount numeric) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_accounts a where a.id=p_account and a.status='active' and a.collectable) and plone27_available(p_account)>=p_amount $$;

-- Suma meses a una fecha conservando el día de anclaje (31 → 30/28 si el mes es más corto)
create or replace function plone27_add_months(p_from date,p_months int,p_anchor int) returns date language plpgsql stable as $$
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
create or replace function plone27_fee_cap() returns trigger language plpgsql as $$ begin
  if new.method='percent' and new.rate>(plone27_setting('tasas_transferencia_max_pct')#>>'{}')::numeric
    then raise exception 'La tasa de transferencia supera el tope central (Art. 4.3)'; end if;
  return new; end $$;
drop trigger if exists t_fee_cap on plone27_fee_rules;
drop trigger if exists t_fee_cap on plone27_fee_rules;
create trigger t_fee_cap before insert or update on plone27_fee_rules for each row execute function plone27_fee_cap();

-- ========== 3. MOTOR FISCAL: tramo fijo para cotizaciones, publicación con aprobador, impuestos de entidad ==========
alter table plone27_tax_rule_versions drop constraint if exists plone27_tax_rule_versions_method_check;
do $$ begin alter table plone27_tax_rule_versions add constraint plone27_tax_rule_versions_method_check
  check(method in('percent','fixed','brackets','bracket_flat')); exception when duplicate_object then null; end $$;  -- bracket_flat: todo el bruto al tipo de su tramo (Art. 4.5)

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
declare r record; n int:=0; begin
  if not (plone27_setting('autocobro_habilitado'))::boolean then return 0; end if;
  for r in select t.id,t.account_id,t.amount-t.paid_amount pend from plone27_tax_receipts t
    where t.status in('issued','partial') and not t.disputed and t.due_date<=current_date order by t.due_date,t.id loop
    continue when not plone27_collectable(r.account_id,r.pend);
    begin perform plone27_tax_pay_partial('auto:tax:'||r.id||':'||r.pend,r.id,r.pend,p_actor); n:=n+1;
    exception when others then insert into plone27_incidents(kind,detail) values('autocobro_fallido',jsonb_build_object('recibo',r.id,'err',sqlerrm)); end;
  end loop; return n; end $$;

create or replace function plone27_autocollect_debts(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
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
declare n int; begin
  with x as(update plone27_rbu_bonuses set status='expired' where status='available' and expires_on<=current_date returning 1)
  select count(*) into n from x; return n; end $$;

-- Reclamación manual por el propio titular. Fondos desde la Cuenta de Reserva (financiada por cotizaciones).
create or replace function plone27_rbu_claim(p_bonus uuid,p_user uuid,p_key text) returns uuid language plpgsql security definer set search_path=public as $$
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
create or replace function plone27_accrue_interest(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare n int:=0; a record; i numeric; begin
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
create or replace function plone27_receipt_routing() returns trigger language plpgsql as $$ begin
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
declare v plone27_tax_rule_versions; begin
  select * into v from plone27_tax_rule_versions where id=p_version for update;
  if v.id is null or v.status<>'draft' then raise exception 'La versión no está en borrador'; end if;
  if p_approver is null or p_approver is not distinct from v.author then raise exception 'Publicar exige un aprobador distinto del autor'; end if;
  update plone27_tax_rule_versions set status='published',approver=p_approver,published_at=now(),fingerprint=plone27_version_fp(p_version) where id=p_version;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_publish','tax_version',p_version::text,jsonb_build_object('approver',p_approver));
end $$;

-- Tramos inmutables una vez publicada la versión (las evaluaciones también son de solo añadir)
create or replace function plone27_bracket_guard() returns trigger language plpgsql as $$
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
create or replace function plone27_set_junior_payer(p_bank uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
  if not exists(select 1 from plone27_banks where id=p_bank and main_account is not null) then raise exception 'La entidad necesita cuenta principal'; end if;
  insert into plone27_config(key,value) values('entidad_capitalia',p_bank::text) on conflict(key) do update set value=excluded.value;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'junior_payer','bank',p_bank::text);
end $$;

create or replace function plone27_junior_tax_payer() returns uuid language plpgsql stable security definer set search_path=public as $$
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
declare aid uuid; begin
  if not exists(select 1 from plone27_accounts where id=p_account and kind in('business','personal') and status='active') then raise exception 'La actividad requiere una cuenta activa'; end if;
  insert into plone27_activities(account_id,category) values(p_account,p_category) returning id into aid;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'activity_register','activity',aid::text); return aid; end $$;

create or replace function plone27_iaep_monthly(p_period date,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
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

create or replace function plone27_institutional_set(p_account uuid,p_motivo text,p_junior boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  if not exists(select 1 from plone27_accounts where id=p_account) then raise exception 'Cuenta inexistente'; end if;
  insert into plone27_institutional_accounts(account_id,motivo,puede_operar_junior,aprobado_por) values(p_account,p_motivo,coalesce(p_junior,false),p_actor)
    on conflict(account_id) do update set motivo=excluded.motivo,puede_operar_junior=excluded.puede_operar_junior,aprobado_por=excluded.aprobado_por;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'institutional_set','account',p_account::text,jsonb_build_object('junior',p_junior,'motivo',p_motivo));
end $$;

-- Junior: solo las cuentas institucionales marcadas pueden operar con cuentas Junior (junior con junior sigue igual)
create or replace function plone27_junior_counterparty() returns trigger language plpgsql security definer set search_path=public as $$ begin
  if exists(select 1 from (select distinct n.transaction_id from new_rows n join plone27_transactions t on t.id=n.transaction_id where t.kind<>'reversal') x
    where exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind='junior')
      and exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
                 where e.transaction_id=x.transaction_id and a.kind in('personal','shared','business')
                   and not exists(select 1 from plone27_institutional_accounts i where i.account_id=a.id and i.puede_operar_junior)))
  then raise exception 'Cuenta Junior: no puede enviar ni recibir de cuentas de clientes habituales'; end if;
  return null; end $$;

-- Destinos de cada impuesto: solo cuentas institucionales
create or replace function plone27_tax_set_destination(p_code text,p_account uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
declare old uuid; begin
  if not plone27_es_institucional(p_account) then raise exception 'El destino debe ser una cuenta institucional'; end if;
  select collector_account into old from plone27_tax_rules where code=p_code;
  if not found then raise exception 'Impuesto desconocido: %',p_code; end if;
  update plone27_tax_rules set collector_account=p_account where code=p_code;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_destination','tax_rule',p_code,jsonb_build_object('anterior',old,'nuevo',p_account));
end $$;

-- Cuentas de configuración (IBAN de tributos y origen de la RBU). Solo institucionales.
create or replace function plone27_config_set(p_key text,p_account uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
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
create or replace function plone27_iva_propose(p_finding uuid,p_accion text,p_motivo text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
  if p_accion not in('regularizar','descartar') then raise exception 'Acción no válida'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  update plone27_iva_findings set propuesta_accion=p_accion,motivo=p_motivo,propuesto_por=p_actor where id=p_finding and status='abierto';
  if not found then raise exception 'Hallazgo no abierto'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_propose','finding',p_finding::text,jsonb_build_object('accion',p_accion,'motivo',p_motivo));
end $$;

create or replace function plone27_iva_approve(p_finding uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
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
  check(kind in('recibo','regularizacion','recargo','rectificacion')); exception when duplicate_object then null; end $$;
alter table plone27_tax_certificates add column if not exists reemplaza uuid references plone27_tax_certificates(id),
  add column if not exists motivo text;
create index if not exists plone27_cert_subject_idx on plone27_tax_certificates(subject_id,seq);

create or replace function plone27_cert_insert(p_kind text,p_subject uuid,p_version uuid,p_base numeric,p_amount numeric,p_inputs jsonb,p_reemplaza uuid,p_motivo text)
returns uuid language plpgsql security definer set search_path=public as $$
declare prev text; fp text; bt text:=p_base::numeric(18,2)::text; am text:=p_amount::numeric(18,2)::text; h text; cid uuid; begin
  perform pg_advisory_xact_lock(hashtext('plone27_cert'));
  select hash into prev from plone27_tax_certificates order by seq desc limit 1; prev:=coalesce(prev,'GENESIS');
  fp:=(select fingerprint from plone27_tax_rule_versions where id=p_version);
  h:=encode(sha256(convert_to(plone27_cert_text(prev,p_kind,p_subject,p_version,fp,bt,am,p_inputs),'utf8')),'hex');
  insert into plone27_tax_certificates(kind,subject_id,version_id,fingerprint,base,amount,inputs,prev_hash,hash,reemplaza,motivo)
    values(p_kind,p_subject,p_version,fp,p_base,p_amount,p_inputs,prev,h,p_reemplaza,p_motivo) returning id into cid;
  return cid; end $$;

create or replace function plone27_cert_append(p_kind text,p_subject uuid,p_version uuid,p_base numeric,p_amount numeric,p_inputs jsonb) returns uuid
language plpgsql security definer set search_path=public as $$ begin
  return plone27_cert_insert(p_kind,p_subject,p_version,p_base,p_amount,p_inputs,null,null); end $$;

create or replace function plone27_cert_receipt_update() returns trigger language plpgsql security definer set search_path=public as $$
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
declare acc uuid; begin
  select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_rbu_origen';
  if acc is null then acc:=plone27_reserve_account(); end if;
  return acc; end $$;

create or replace function plone27_rbu_claim(p_bonus uuid,p_user uuid,p_key text) returns uuid language plpgsql security definer set search_path=public as $$
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
declare smi numeric; ek text; wk text; begin
  select kind into ek from plone27_accounts where id=new.employer_account and bank_id=new.bank_id;
  select kind into wk from plone27_accounts where id=new.worker_account and bank_id=new.bank_id;
  if ek is distinct from 'business' then raise exception 'La cuenta empleadora debe ser de empresa de la entidad'; end if;
  if wk is distinct from 'personal' then raise exception 'La cuenta del trabajador debe ser personal de la entidad'; end if;
  smi:=(plone27_setting('smi_mensual_completa_pz',new.bank_id)#>>'{}')::numeric;
  if new.gross_monthly<smi then raise exception 'Contrato no válido: el bruto mensual está por debajo del SMI (% Pz al mes)',smi; end if;
  return new; end $$;

create or replace function plone27_payroll_run(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
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
do $$ begin alter table plone27_sales add constraint plone27_sales_origin_check check(origin in('plataforma','regularizada','presunta')); exception when duplicate_object then null; end $$;
alter table plone27_iva_findings drop constraint if exists plone27_iva_findings_status_check;
do $$ begin alter table plone27_iva_findings add constraint plone27_iva_findings_status_check check(status in('abierto','presumido','regularizado','descartado')); exception when duplicate_object then null; end $$;
alter table plone27_tax_certificates drop constraint if exists plone27_tax_certificates_kind_check;
do $$ begin alter table plone27_tax_certificates add constraint plone27_tax_certificates_kind_check check(kind in('recibo','regularizacion','recargo','rectificacion','cierre')); exception when duplicate_object then null; end $$;

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

create or replace function plone27_iva_propose(p_finding uuid,p_accion text,p_motivo text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
  if p_accion not in('regularizar','descartar') then raise exception 'Acción no válida'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  update plone27_iva_findings set propuesta_accion=p_accion,motivo=p_motivo,propuesto_por=p_actor
   where id=p_finding and (status='abierto' or (status='presumido' and p_accion='descartar'));
  if not found then raise exception 'Hallazgo no abierto (o presumido solo se puede descartar)'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_propose','finding',p_finding::text,jsonb_build_object('accion',p_accion,'motivo',p_motivo));
end $$;

-- Aprobación: regularizar registra la venta (se liquida en el cierre del mes); descartar un hallazgo presumido crea un ajuste para el siguiente cierre.
create or replace function plone27_iva_approve(p_finding uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
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

create or replace function plone27_config_set(p_key text,p_account uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
  if p_key not in('cuenta_tributos','cuenta_rbu_origen','pagador_impuestos_junior') then raise exception 'Clave no permitida: %',p_key; end if;
  if not plone27_es_institucional(p_account) then raise exception 'La cuenta debe ser institucional'; end if;
  insert into plone27_config(key,value) values(p_key,p_account::text) on conflict(key) do update set value=excluded.value;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'config_set','config',p_key,jsonb_build_object('cuenta',p_account));
end $$;

-- ========== 9. ESTADÍSTICAS (una fila por fecha, área, métrica y dimensión) ==========
create or replace function plone27_estadisticas_dia(p_fecha date,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
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
create or replace view plone27_v_movimientos with(security_invoker=true) as
  select e.id,e.created_at,t.id tx_id,t.kind,t.status,t.memo,e.direction,e.amount,
         a.id account_id,a.iban,a.name account_name,a.kind account_kind,a.owner_user,b.code bank_code,b.name bank_name
  from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
  join plone27_accounts a on a.id=e.account_id left join plone27_banks b on b.id=a.bank_id;

create or replace view plone27_v_declaraciones with(security_invoker=true) as
  select d.id,p.periodo,a.iban,a.name account_name,a.kind account_kind,d.impuesto,d.base,d.importe,d.estado,d.fuente,
         d.motivo_retencion,d.saldo_arrastre,d.receipt_id,d.aprobado_por,d.aprobado_at
  from plone27_declaraciones d join plone27_periodos p on p.id=d.periodo_id join plone27_accounts a on a.id=d.account_id;

create or replace view plone27_v_recibos with(security_invoker=true) as
  select r.id,r.ref,r.created_at,ru.code impuesto,a.iban,a.kind account_kind,r.base,r.amount,r.paid_amount,r.status,r.due_date,
         r.obligor_account,r.operation_ref
  from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
  join plone27_tax_rules ru on ru.id=v.rule_id join plone27_accounts a on a.id=r.account_id;

-- ========== 11. EJECUCIÓN DIARIA: cierre mensual y estadísticas de ayer ==========
create or replace function plone27_finanzas_daily(p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
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
create or replace view plone27_listo as
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
