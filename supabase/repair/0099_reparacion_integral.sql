-- ====================================================================================================
-- PLACETA ONE · 0099 · REPARACIÓN INTEGRAL DE LA BASE DE DATOS (idempotente)
-- Pégalo ENTERO en Supabase → SQL Editor y pulsa Run. Puedes ejecutarlo las veces que quieras.
--   · Crea lo que falte: tablas, columnas, claves, índices, funciones, vistas, triggers y políticas RLS.
--   · Sustituye todas las funciones por su última versión (incluye el arreglo de plone27_certification_report).
--   · No borra ni modifica datos existentes. Claves foráneas y checks nuevos se añaden NOT VALID
--     (se aplican a los datos nuevos sin fallar por datos antiguos).
--   · Da de alta como admin a junta@laplaceta.org si existe en Authentication → Users.
--   · Termina con un INFORME: filas «ERROR/AVISO» = lo que no se pudo aplicar; la última fila resume
--     las consultas del panel que se han verificado una a una.
-- Requisito: las tablas auth.* de Supabase (ya existen en cualquier proyecto).
-- ====================================================================================================
set check_function_bodies = off;
set statement_timeout = 0;
set search_path = public;

create temp table _p27_log(n serial, nivel text, que text, detalle text);

create function pg_temp.ddl(p_sql text, p_what text, p_fallback text default null) returns void language plpgsql as $f$
begin
  begin execute p_sql;
  exception
    when duplicate_object or duplicate_table or duplicate_column then null;
    when others then
      if p_fallback is not null then
        begin execute p_fallback; execute p_sql;
        exception when others then insert into _p27_log(nivel,que,detalle) values('ERROR',p_what,sqlerrm); end;
      else insert into _p27_log(nivel,que,detalle) values('AVISO',p_what,sqlerrm); end if;
  end;
end $f$;

create function pg_temp.col(t text, c text, d text) returns void language plpgsql as $f$
begin execute format('alter table public.%I add column if not exists %I %s',t,c,d);
exception when others then insert into _p27_log(nivel,que,detalle) values('AVISO','columna '||t||'.'||c,sqlerrm); end $f$;

create function pg_temp.k(t text, n text, ty text, d text) returns void language plpgsql as $f$
begin
  if exists(select 1 from pg_constraint x where x.conname=n and x.conrelid=('public.'||t)::regclass) then return; end if;
  if ty='p' and exists(select 1 from pg_constraint x where x.contype='p' and x.conrelid=('public.'||t)::regclass) then return; end if;
  execute format('alter table public.%I add constraint %I %s%s',t,n,d,case when ty in('c','f') then ' not valid' else '' end);
exception when duplicate_object or duplicate_table then null;
  when others then insert into _p27_log(nivel,que,detalle) values('AVISO','restricción '||t||'.'||n,sqlerrm); end $f$;

-- ===== 1. TABLAS (se crean si faltan) =====
select pg_temp.ddl($q$create table if not exists public.plone27_account_members (account_id uuid not null, user_id uuid not null, role text not null)$q$, $q$crear tabla plone27_account_members$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_accounts (id uuid default gen_random_uuid() not null, bank_id uuid, kind text not null, name text not null, owner_user uuid, status text default 'active'::text not null, daily_limit numeric(18,2), allow_negative boolean default false not null, created_at timestamp with time zone default now(), iban text, product_id uuid, credit_limit numeric(18,2) default 0 not null, customer_id uuid, collectable boolean default true not null)$q$, $q$crear tabla plone27_accounts$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_activities (id uuid default gen_random_uuid() not null, account_id uuid not null, category text not null, registered_at date default CURRENT_DATE not null, status text default 'active'::text not null, created_at timestamp with time zone default now() not null)$q$, $q$crear tabla plone27_activities$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_api_clients (id uuid default gen_random_uuid() not null, bank_id uuid not null, name text not null, key_hash text not null, scopes text[] default '{}'::text[] not null, rate_limit integer default 60 not null, active boolean default true not null, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_api_clients$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_api_usage (client_id uuid not null, minute timestamp with time zone not null, hits integer default 0 not null)$q$, $q$crear tabla plone27_api_usage$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_approvals (id uuid default gen_random_uuid() not null, subject text not null, subject_id uuid, requested_by uuid, approved_by uuid, reason text not null, result text, at timestamp with time zone default now(), ref text)$q$, $q$crear tabla plone27_approvals$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_audit_log (id bigint generated always as identity not null, actor uuid, action text not null, entity text, entity_id text, detail jsonb, at timestamp with time zone default now())$q$, $q$crear tabla plone27_audit_log$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_bank_settings (bank_id uuid not null, key text not null, value jsonb not null)$q$, $q$crear tabla plone27_bank_settings$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_banks (id uuid default gen_random_uuid() not null, code text not null, name text not null, active boolean default true, description text, status text default 'draft'::text not null, valid_from date, valid_to date, approved_by uuid, config jsonb default '{}'::jsonb not null, main_account uuid, tax_account uuid)$q$, $q$crear tabla plone27_banks$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_batch_items (id uuid default gen_random_uuid() not null, batch_id uuid not null, to_account uuid not null, amount numeric(18,2) not null, status text default 'pending'::text not null, error text)$q$, $q$crear tabla plone27_batch_items$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_batches (id uuid default gen_random_uuid() not null, kind text not null, from_account uuid not null, status text default 'open'::text not null)$q$, $q$crear tabla plone27_batches$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_budgets (id uuid default gen_random_uuid() not null, name text, period daterange, approved numeric(18,2), committed numeric(18,2) default 0, executed numeric(18,2) default 0, restricted boolean default false)$q$, $q$crear tabla plone27_budgets$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_card_charges (id uuid default gen_random_uuid() not null, card_id uuid not null, merchant_account uuid not null, amount numeric(18,2) not null, status text default 'authorized'::text not null, reservation_id uuid, at timestamp with time zone default now())$q$, $q$crear tabla plone27_card_charges$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_card_designs (id uuid default gen_random_uuid() not null, name text not null, tier text not null, price numeric(18,2) default 0 not null, license_fee numeric(18,2) default 0 not null, revenue_account uuid, owner uuid, status text default 'draft'::text not null, elements jsonb default '{}'::jsonb not null)$q$, $q$crear tabla plone27_card_designs$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_card_orders (id uuid default gen_random_uuid() not null, card_id uuid not null, status text default 'ordered'::text not null, updated_at timestamp with time zone default now())$q$, $q$crear tabla plone27_card_orders$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_cards (id uuid default gen_random_uuid() not null, account_id uuid not null, kind text not null, status text default 'active'::text not null, design_id uuid, credit_limit numeric(18,2), card_ref text, is_test boolean default false not null, expires date, last4 text, pan_hash text)$q$, $q$crear tabla plone27_cards$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_config (key text not null, value text not null)$q$, $q$crear tabla plone27_config$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_contracts (id uuid default gen_random_uuid() not null, bank_id uuid not null, employer_account uuid not null, worker_account uuid not null, worker_user uuid not null, gross_monthly numeric(18,2) not null, full_time boolean default true not null, start_date date not null, pay_day integer not null, next_pay date not null, status text default 'active'::text not null, approved_by uuid not null, created_at timestamp with time zone default now() not null)$q$, $q$crear tabla plone27_contracts$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_counters (kind text not null, scope text not null, last bigint not null)$q$, $q$crear tabla plone27_counters$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_customers (id uuid default gen_random_uuid() not null, dip text not null, full_name text not null, bank_id uuid, user_id uuid, status text default 'active'::text not null, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_customers$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_debts (id uuid default gen_random_uuid() not null, account_id uuid, principal numeric(18,2) not null, authorized_charges numeric(18,2) default 0, paid numeric(18,2) default 0, due_date date, disputed boolean default false, authorized_by uuid not null, reason text not null, ref text, creditor_account uuid, origin text)$q$, $q$crear tabla plone27_debts$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_design_purchases (design_id uuid not null, account_id uuid not null, tx uuid)$q$, $q$crear tabla plone27_design_purchases$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_disputes (id uuid default gen_random_uuid() not null, ref text, subject_type text not null, subject_id uuid not null, account_id uuid, reason text not null, status text default 'open'::text not null, opened_by uuid, opened_at timestamp with time zone default now(), due_at timestamp with time zone, resolution text, resolved_by uuid, resolved_at timestamp with time zone)$q$, $q$crear tabla plone27_disputes$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_fee_rules (id uuid default gen_random_uuid() not null, bank_id uuid, op_type text default 'transfer'::text not null, method text not null, rate numeric(9,4) not null, min_amount numeric(18,2), max_amount numeric(18,2), payer text not null, bank_pay_account uuid, beneficiary_account uuid not null, valid_from date not null, valid_to date, approved_by uuid)$q$, $q$crear tabla plone27_fee_rules$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_grant_programs (id uuid default gen_random_uuid() not null, name text not null, kind text, budget numeric(18,2) not null, funding_account uuid)$q$, $q$crear tabla plone27_grant_programs$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_grants (id uuid default gen_random_uuid() not null, program_id uuid, beneficiary_account uuid, granted numeric(18,2) not null, approved numeric(18,2) default 0 not null, paid numeric(18,2) default 0 not null, ref text)$q$, $q$crear tabla plone27_grants$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_incidents (id uuid default gen_random_uuid() not null, kind text, detail jsonb, status text default 'open'::text, at timestamp with time zone default now(), ref text)$q$, $q$crear tabla plone27_incidents$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_institutional_accounts (account_id uuid not null, motivo text not null, puede_operar_junior boolean default false not null, aprobado_por uuid, created_at timestamp with time zone default now() not null)$q$, $q$crear tabla plone27_institutional_accounts$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_invoices (id uuid default gen_random_uuid() not null, ref text, account_id uuid, concept text, amount numeric(18,2) not null, status text default 'issued'::text)$q$, $q$crear tabla plone27_invoices$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_issued_ids (identifier text not null, kind text not null, at timestamp with time zone default now())$q$, $q$crear tabla plone27_issued_ids$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_iva_findings (id uuid default gen_random_uuid() not null, ref_key text not null, kind text not null, tx uuid, account_id uuid not null, counterpart_account uuid, amount numeric(18,2) not null, iva_due numeric(18,2), severity text not null, status text default 'abierto'::text not null, propuesta_accion text, propuesto_por uuid, motivo text, aprobado_por uuid, receipt_id uuid, detected_at timestamp with time zone default now() not null, resolved_at timestamp with time zone)$q$, $q$crear tabla plone27_iva_findings$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_junior_profiles (customer_id uuid not null, birth_date date not null, guardian_user uuid not null, per_tx_limit numeric(18,2), daily_limit numeric(18,2), monthly_limit numeric(18,2), card_enabled boolean default true not null, locked boolean default false not null)$q$, $q$crear tabla plone27_junior_profiles$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_juniors (account_id uuid not null, birth_date date not null, guardian_user uuid not null, per_tx_limit numeric(18,2) not null)$q$, $q$crear tabla plone27_juniors$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_justifications (id uuid default gen_random_uuid() not null, grant_id uuid not null, transaction_id uuid not null, invoice_ref text, amount numeric(18,2) not null, status text default 'pending'::text, ref text, reimb_ref text)$q$, $q$crear tabla plone27_justifications$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_late_accruals (source text not null, ref uuid not null, accrued_until timestamp with time zone not null)$q$, $q$crear tabla plone27_late_accruals$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_ledger_entries (id bigint generated always as identity not null, transaction_id uuid not null, account_id uuid not null, direction text not null, amount numeric(18,2) not null, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_ledger_entries$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_numbering_formats (kind text not null, version integer not null, prefix text not null, year_scoped boolean not null, width integer not null, status text default 'draft'::text not null, reason text, author uuid, approved_by uuid, valid_from date default CURRENT_DATE not null)$q$, $q$crear tabla plone27_numbering_formats$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_outbox (id bigint generated always as identity not null, event text not null, bank_ids uuid[] default '{}'::uuid[] not null, payload jsonb, status text default 'pending'::text not null, attempts integer default 0 not null, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_outbox$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_payslips (id uuid default gen_random_uuid() not null, contract_id uuid not null, pay_date date not null, gross numeric(18,2) not null, worker_contrib numeric(18,2) not null, employer_contrib numeric(18,2) not null, irp numeric(18,2) not null, net numeric(18,2) not null, tx uuid, created_at timestamp with time zone default now() not null)$q$, $q$crear tabla plone27_payslips$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_plan_items (id uuid default gen_random_uuid() not null, plan_id uuid not null, seq integer not null, due_date date not null, principal_part numeric(18,2) not null, interest_part numeric(18,2) default 0 not null, status text default 'pending'::text not null, attempts integer default 0 not null, paid_tx uuid, paid_at timestamp with time zone)$q$, $q$crear tabla plone27_plan_items$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_plans (id uuid default gen_random_uuid() not null, idem_key text not null, kind text not null, bank_id uuid not null, debtor_account uuid not null, beneficiary_account uuid not null, lender_account uuid, principal numeric(18,2) not null, annual_rate_pct numeric(9,4) default 0 not null, installments integer, start_date date not null, anchor_day integer not null, next_due date, status text default 'active'::text not null, approved_by uuid not null, created_by uuid, created_at timestamp with time zone default now() not null)$q$, $q$crear tabla plone27_plans$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_policies (id uuid default gen_random_uuid() not null, ref text, kind text not null, name text not null, scope text not null, bank_id uuid, customer_id uuid, dip text, params jsonb default '{}'::jsonb not null, valid_from date default CURRENT_DATE not null, valid_to date, status text default 'draft'::text not null, reason text, approved_by uuid, created_by uuid, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_policies$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_products (id uuid default gen_random_uuid() not null, code text not null, bank_id uuid not null, kind text not null, name text not null, description text, status text default 'draft'::text not null, daily_limit numeric(18,2), credit_limit numeric(18,2), monthly_fee numeric(18,2) default 0 not null, fee_account uuid, interest_rate numeric(9,4) default 0 not null, min_age integer, requires_guardian boolean default false not null, valid_from date, valid_to date, terms jsonb default '{}'::jsonb not null, approved_by uuid, created_by uuid, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_products$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_rbu_bonuses (id uuid default gen_random_uuid() not null, owner_user uuid not null, wallet_account uuid not null, week_start date not null, amount numeric(18,2) not null, status text default 'available'::text not null, expires_on date not null, claimed_at timestamp with time zone, claimed_tx uuid)$q$, $q$crear tabla plone27_rbu_bonuses$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_reservations (id uuid default gen_random_uuid() not null, account_id uuid not null, amount numeric(18,2) not null, reason text, status text default 'active'::text, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_reservations$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_sales (tx uuid not null, seller_account uuid not null, buyer_account uuid, base numeric(18,2) not null, iva numeric(18,2), origin text not null, created_at timestamp with time zone default now() not null)$q$, $q$crear tabla plone27_sales$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_scheduled (id uuid default gen_random_uuid() not null, from_account uuid, to_account uuid, amount numeric(18,2) not null, run_at timestamp with time zone not null, recurrence interval, status text default 'active'::text, memo text)$q$, $q$crear tabla plone27_scheduled$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_setting_changes (id uuid default gen_random_uuid() not null, key text not null, bank_id uuid, new_value jsonb not null, old_value jsonb, reason text not null, proposed_by uuid, approved_by uuid, status text default 'pending'::text not null, at timestamp with time zone default now())$q$, $q$crear tabla plone27_setting_changes$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_settings (key text not null, category text not null, description text not null, vtype text not null, allowed text[], min_v numeric, max_v numeric, value jsonb not null, sensitive boolean default false not null, bank_overridable boolean default true not null, version integer default 1 not null, updated_at timestamp with time zone default now())$q$, $q$crear tabla plone27_settings$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_settlements (id uuid default gen_random_uuid() not null, ref text, bank_id uuid not null, period_from date not null, period_to date not null, evaluated numeric(18,2), collected numeric(18,2), pending numeric(18,2), refunded numeric(18,2))$q$, $q$crear tabla plone27_settlements$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_staff (user_id uuid not null, role text not null, active boolean default true not null, created_at timestamp with time zone default now(), bank_id uuid)$q$, $q$crear tabla plone27_staff$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_subscriptions (id uuid default gen_random_uuid() not null, account_id uuid not null, product_id uuid, status text default 'past_due'::text not null, period_start date, period_end date default CURRENT_DATE not null, auto_renew boolean default true not null, renewals integer default 0 not null, last_tx uuid, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_subscriptions$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_adjustments (id uuid default gen_random_uuid() not null, receipt_id uuid not null, new_version_id uuid not null, original_amount numeric(18,2), corrected_amount numeric(18,2), diff numeric(18,2), status text default 'simulated'::text, created_by uuid, approved_by uuid, adj_receipt uuid, adj_tx uuid, ref text)$q$, $q$crear tabla plone27_tax_adjustments$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_brackets (version_id uuid not null, from_amount numeric(18,2) not null, to_amount numeric(18,2), rate numeric(9,4) not null)$q$, $q$crear tabla plone27_tax_brackets$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_certificates (seq bigint generated always as identity not null, id uuid default gen_random_uuid() not null, kind text not null, subject_id uuid not null, version_id uuid, fingerprint text, base numeric(18,2) not null, amount numeric(18,2) not null, inputs jsonb not null, prev_hash text not null, hash text not null, created_at timestamp with time zone default now() not null, reemplaza uuid, motivo text)$q$, $q$crear tabla plone27_tax_certificates$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_distribution (id uuid default gen_random_uuid() not null, rule_id uuid not null, account_id uuid not null, pct numeric(5,2) not null, approved_by uuid)$q$, $q$crear tabla plone27_tax_distribution$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_evaluations (id uuid default gen_random_uuid() not null, event_key text not null, rule_id uuid, rule_version_id uuid, account_id uuid, pathway text not null, base numeric(18,2), amount numeric(18,2), status text default 'calculated'::text not null, created_at timestamp with time zone default now())$q$, $q$crear tabla plone27_tax_evaluations$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_exemptions (id uuid default gen_random_uuid() not null, rule_id uuid, account_id uuid, valid_from date not null, valid_to date, reason text not null, legal_basis text not null, approved_by uuid not null)$q$, $q$crear tabla plone27_tax_exemptions$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_receipts (id uuid default gen_random_uuid() not null, rule_version_id uuid not null, account_id uuid not null, base numeric(18,2) not null, amount numeric(18,2) not null, status text default 'issued'::text, due_date date, original_receipt uuid, created_at timestamp with time zone default now(), evaluation_id uuid, paid_tx uuid, refunded numeric(18,2) default 0 not null, ref text, paid_amount numeric(18,2) default 0 not null, disputed boolean default false not null, obligor_account uuid, operation_ref text)$q$, $q$crear tabla plone27_tax_receipts$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_rule_versions (id uuid default gen_random_uuid() not null, rule_id uuid not null, version integer not null, method text not null, rate numeric(9,4) not null, min_amount numeric(18,2), max_amount numeric(18,2), valid_from date not null, valid_to date, status text default 'draft'::text not null, reason text not null, author uuid, approver uuid, published_at timestamp with time zone, scope_bank uuid, scope_op text, retro_mode text default 'prohibited'::text not null, fingerprint text)$q$, $q$crear tabla plone27_tax_rule_versions$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_tax_rules (id uuid default gen_random_uuid() not null, code text not null, name text not null, max_rate numeric(9,4), collector_account uuid)$q$, $q$crear tabla plone27_tax_rules$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_transactions (id uuid default gen_random_uuid() not null, kind text not null, status text default 'posted'::text not null, idempotency_key text not null, reverses uuid, memo text, created_by uuid, created_at timestamp with time zone default now(), ref text, transfer_ref text, req_hash text)$q$, $q$crear tabla plone27_transactions$q$);
select pg_temp.ddl($q$create table if not exists public.plone27_webhooks (id uuid default gen_random_uuid() not null, bank_id uuid not null, url text not null, secret text not null, events text[] default '{*}'::text[] not null, active boolean default true not null)$q$, $q$crear tabla plone27_webhooks$q$);
-- ===== 2. COLUMNAS que falten en tablas ya existentes =====
select pg_temp.col($q$plone27_account_members$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_account_members$q$,$q$user_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_account_members$q$,$q$role$q$,$q$text$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$owner_user$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$status$q$,$q$text default 'active'::text not null$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$daily_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$allow_negative$q$,$q$boolean default false not null$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$iban$q$,$q$text$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$product_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$credit_limit$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$customer_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_accounts$q$,$q$collectable$q$,$q$boolean default true not null$q$);
select pg_temp.col($q$plone27_activities$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_activities$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_activities$q$,$q$category$q$,$q$text$q$);
select pg_temp.col($q$plone27_activities$q$,$q$registered_at$q$,$q$date default CURRENT_DATE not null$q$);
select pg_temp.col($q$plone27_activities$q$,$q$status$q$,$q$text default 'active'::text not null$q$);
select pg_temp.col($q$plone27_activities$q$,$q$created_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$key_hash$q$,$q$text$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$scopes$q$,$q$text[] default '{}'::text[] not null$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$rate_limit$q$,$q$integer default 60 not null$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$active$q$,$q$boolean default true not null$q$);
select pg_temp.col($q$plone27_api_clients$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_api_usage$q$,$q$client_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_api_usage$q$,$q$minute$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_api_usage$q$,$q$hits$q$,$q$integer default 0 not null$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$subject$q$,$q$text$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$subject_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$requested_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$result$q$,$q$text$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_approvals$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_audit_log$q$,$q$id$q$,$q$bigint$q$);
select pg_temp.col($q$plone27_audit_log$q$,$q$actor$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_audit_log$q$,$q$action$q$,$q$text$q$);
select pg_temp.col($q$plone27_audit_log$q$,$q$entity$q$,$q$text$q$);
select pg_temp.col($q$plone27_audit_log$q$,$q$entity_id$q$,$q$text$q$);
select pg_temp.col($q$plone27_audit_log$q$,$q$detail$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_audit_log$q$,$q$at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_bank_settings$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_bank_settings$q$,$q$key$q$,$q$text$q$);
select pg_temp.col($q$plone27_bank_settings$q$,$q$value$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_banks$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_banks$q$,$q$code$q$,$q$text$q$);
select pg_temp.col($q$plone27_banks$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_banks$q$,$q$active$q$,$q$boolean default true$q$);
select pg_temp.col($q$plone27_banks$q$,$q$description$q$,$q$text$q$);
select pg_temp.col($q$plone27_banks$q$,$q$status$q$,$q$text default 'draft'::text not null$q$);
select pg_temp.col($q$plone27_banks$q$,$q$valid_from$q$,$q$date$q$);
select pg_temp.col($q$plone27_banks$q$,$q$valid_to$q$,$q$date$q$);
select pg_temp.col($q$plone27_banks$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_banks$q$,$q$config$q$,$q$jsonb default '{}'::jsonb not null$q$);
select pg_temp.col($q$plone27_banks$q$,$q$main_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_banks$q$,$q$tax_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_batch_items$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_batch_items$q$,$q$batch_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_batch_items$q$,$q$to_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_batch_items$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_batch_items$q$,$q$status$q$,$q$text default 'pending'::text not null$q$);
select pg_temp.col($q$plone27_batch_items$q$,$q$error$q$,$q$text$q$);
select pg_temp.col($q$plone27_batches$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_batches$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_batches$q$,$q$from_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_batches$q$,$q$status$q$,$q$text default 'open'::text not null$q$);
select pg_temp.col($q$plone27_budgets$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_budgets$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_budgets$q$,$q$period$q$,$q$daterange$q$);
select pg_temp.col($q$plone27_budgets$q$,$q$approved$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_budgets$q$,$q$committed$q$,$q$numeric(18,2) default 0$q$);
select pg_temp.col($q$plone27_budgets$q$,$q$executed$q$,$q$numeric(18,2) default 0$q$);
select pg_temp.col($q$plone27_budgets$q$,$q$restricted$q$,$q$boolean default false$q$);
select pg_temp.col($q$plone27_card_charges$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_card_charges$q$,$q$card_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_card_charges$q$,$q$merchant_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_card_charges$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_card_charges$q$,$q$status$q$,$q$text default 'authorized'::text not null$q$);
select pg_temp.col($q$plone27_card_charges$q$,$q$reservation_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_card_charges$q$,$q$at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$tier$q$,$q$text$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$price$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$license_fee$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$revenue_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$owner$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$status$q$,$q$text default 'draft'::text not null$q$);
select pg_temp.col($q$plone27_card_designs$q$,$q$elements$q$,$q$jsonb default '{}'::jsonb not null$q$);
select pg_temp.col($q$plone27_card_orders$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_card_orders$q$,$q$card_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_card_orders$q$,$q$status$q$,$q$text default 'ordered'::text not null$q$);
select pg_temp.col($q$plone27_card_orders$q$,$q$updated_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_cards$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_cards$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_cards$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_cards$q$,$q$status$q$,$q$text default 'active'::text not null$q$);
select pg_temp.col($q$plone27_cards$q$,$q$design_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_cards$q$,$q$credit_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_cards$q$,$q$card_ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_cards$q$,$q$is_test$q$,$q$boolean default false not null$q$);
select pg_temp.col($q$plone27_cards$q$,$q$expires$q$,$q$date$q$);
select pg_temp.col($q$plone27_cards$q$,$q$last4$q$,$q$text$q$);
select pg_temp.col($q$plone27_cards$q$,$q$pan_hash$q$,$q$text$q$);
select pg_temp.col($q$plone27_config$q$,$q$key$q$,$q$text$q$);
select pg_temp.col($q$plone27_config$q$,$q$value$q$,$q$text$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$employer_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$worker_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$worker_user$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$gross_monthly$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$full_time$q$,$q$boolean default true not null$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$start_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$pay_day$q$,$q$integer$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$next_pay$q$,$q$date$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$status$q$,$q$text default 'active'::text not null$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_contracts$q$,$q$created_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_counters$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_counters$q$,$q$scope$q$,$q$text$q$);
select pg_temp.col($q$plone27_counters$q$,$q$last$q$,$q$bigint$q$);
select pg_temp.col($q$plone27_customers$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_customers$q$,$q$dip$q$,$q$text$q$);
select pg_temp.col($q$plone27_customers$q$,$q$full_name$q$,$q$text$q$);
select pg_temp.col($q$plone27_customers$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_customers$q$,$q$user_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_customers$q$,$q$status$q$,$q$text default 'active'::text not null$q$);
select pg_temp.col($q$plone27_customers$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_debts$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_debts$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_debts$q$,$q$principal$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_debts$q$,$q$authorized_charges$q$,$q$numeric(18,2) default 0$q$);
select pg_temp.col($q$plone27_debts$q$,$q$paid$q$,$q$numeric(18,2) default 0$q$);
select pg_temp.col($q$plone27_debts$q$,$q$due_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_debts$q$,$q$disputed$q$,$q$boolean default false$q$);
select pg_temp.col($q$plone27_debts$q$,$q$authorized_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_debts$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_debts$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_debts$q$,$q$creditor_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_debts$q$,$q$origin$q$,$q$text$q$);
select pg_temp.col($q$plone27_design_purchases$q$,$q$design_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_design_purchases$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_design_purchases$q$,$q$tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$subject_type$q$,$q$text$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$subject_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$status$q$,$q$text default 'open'::text not null$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$opened_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$opened_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$due_at$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$resolution$q$,$q$text$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$resolved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_disputes$q$,$q$resolved_at$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$op_type$q$,$q$text default 'transfer'::text not null$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$method$q$,$q$text$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$rate$q$,$q$numeric(9,4)$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$min_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$max_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$payer$q$,$q$text$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$bank_pay_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$beneficiary_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$valid_from$q$,$q$date$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$valid_to$q$,$q$date$q$);
select pg_temp.col($q$plone27_fee_rules$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_grant_programs$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_grant_programs$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_grant_programs$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_grant_programs$q$,$q$budget$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_grant_programs$q$,$q$funding_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_grants$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_grants$q$,$q$program_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_grants$q$,$q$beneficiary_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_grants$q$,$q$granted$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_grants$q$,$q$approved$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_grants$q$,$q$paid$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_grants$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_incidents$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_incidents$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_incidents$q$,$q$detail$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_incidents$q$,$q$status$q$,$q$text default 'open'::text$q$);
select pg_temp.col($q$plone27_incidents$q$,$q$at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_incidents$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_institutional_accounts$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_institutional_accounts$q$,$q$motivo$q$,$q$text$q$);
select pg_temp.col($q$plone27_institutional_accounts$q$,$q$puede_operar_junior$q$,$q$boolean default false not null$q$);
select pg_temp.col($q$plone27_institutional_accounts$q$,$q$aprobado_por$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_institutional_accounts$q$,$q$created_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_invoices$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_invoices$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_invoices$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_invoices$q$,$q$concept$q$,$q$text$q$);
select pg_temp.col($q$plone27_invoices$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_invoices$q$,$q$status$q$,$q$text default 'issued'::text$q$);
select pg_temp.col($q$plone27_issued_ids$q$,$q$identifier$q$,$q$text$q$);
select pg_temp.col($q$plone27_issued_ids$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_issued_ids$q$,$q$at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$ref_key$q$,$q$text$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$counterpart_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$iva_due$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$severity$q$,$q$text$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$status$q$,$q$text default 'abierto'::text not null$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$propuesta_accion$q$,$q$text$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$propuesto_por$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$motivo$q$,$q$text$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$aprobado_por$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$receipt_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$detected_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_iva_findings$q$,$q$resolved_at$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$customer_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$birth_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$guardian_user$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$per_tx_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$daily_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$monthly_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$card_enabled$q$,$q$boolean default true not null$q$);
select pg_temp.col($q$plone27_junior_profiles$q$,$q$locked$q$,$q$boolean default false not null$q$);
select pg_temp.col($q$plone27_juniors$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_juniors$q$,$q$birth_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_juniors$q$,$q$guardian_user$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_juniors$q$,$q$per_tx_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$grant_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$transaction_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$invoice_ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$status$q$,$q$text default 'pending'::text$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_justifications$q$,$q$reimb_ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_late_accruals$q$,$q$source$q$,$q$text$q$);
select pg_temp.col($q$plone27_late_accruals$q$,$q$ref$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_late_accruals$q$,$q$accrued_until$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_ledger_entries$q$,$q$id$q$,$q$bigint$q$);
select pg_temp.col($q$plone27_ledger_entries$q$,$q$transaction_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_ledger_entries$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_ledger_entries$q$,$q$direction$q$,$q$text$q$);
select pg_temp.col($q$plone27_ledger_entries$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_ledger_entries$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$version$q$,$q$integer$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$prefix$q$,$q$text$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$year_scoped$q$,$q$boolean$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$width$q$,$q$integer$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$status$q$,$q$text default 'draft'::text not null$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$author$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_numbering_formats$q$,$q$valid_from$q$,$q$date default CURRENT_DATE not null$q$);
select pg_temp.col($q$plone27_outbox$q$,$q$id$q$,$q$bigint$q$);
select pg_temp.col($q$plone27_outbox$q$,$q$event$q$,$q$text$q$);
select pg_temp.col($q$plone27_outbox$q$,$q$bank_ids$q$,$q$uuid[] default '{}'::uuid[] not null$q$);
select pg_temp.col($q$plone27_outbox$q$,$q$payload$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_outbox$q$,$q$status$q$,$q$text default 'pending'::text not null$q$);
select pg_temp.col($q$plone27_outbox$q$,$q$attempts$q$,$q$integer default 0 not null$q$);
select pg_temp.col($q$plone27_outbox$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$contract_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$pay_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$gross$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$worker_contrib$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$employer_contrib$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$irp$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$net$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_payslips$q$,$q$created_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$plan_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$seq$q$,$q$integer$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$due_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$principal_part$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$interest_part$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$status$q$,$q$text default 'pending'::text not null$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$attempts$q$,$q$integer default 0 not null$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$paid_tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plan_items$q$,$q$paid_at$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_plans$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_plans$q$,$q$idem_key$q$,$q$text$q$);
select pg_temp.col($q$plone27_plans$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_plans$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plans$q$,$q$debtor_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plans$q$,$q$beneficiary_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plans$q$,$q$lender_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plans$q$,$q$principal$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_plans$q$,$q$annual_rate_pct$q$,$q$numeric(9,4) default 0 not null$q$);
select pg_temp.col($q$plone27_plans$q$,$q$installments$q$,$q$integer$q$);
select pg_temp.col($q$plone27_plans$q$,$q$start_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_plans$q$,$q$anchor_day$q$,$q$integer$q$);
select pg_temp.col($q$plone27_plans$q$,$q$next_due$q$,$q$date$q$);
select pg_temp.col($q$plone27_plans$q$,$q$status$q$,$q$text default 'active'::text not null$q$);
select pg_temp.col($q$plone27_plans$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plans$q$,$q$created_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_plans$q$,$q$created_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_policies$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_policies$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_policies$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_policies$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_policies$q$,$q$scope$q$,$q$text$q$);
select pg_temp.col($q$plone27_policies$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_policies$q$,$q$customer_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_policies$q$,$q$dip$q$,$q$text$q$);
select pg_temp.col($q$plone27_policies$q$,$q$params$q$,$q$jsonb default '{}'::jsonb not null$q$);
select pg_temp.col($q$plone27_policies$q$,$q$valid_from$q$,$q$date default CURRENT_DATE not null$q$);
select pg_temp.col($q$plone27_policies$q$,$q$valid_to$q$,$q$date$q$);
select pg_temp.col($q$plone27_policies$q$,$q$status$q$,$q$text default 'draft'::text not null$q$);
select pg_temp.col($q$plone27_policies$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_policies$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_policies$q$,$q$created_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_policies$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_products$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_products$q$,$q$code$q$,$q$text$q$);
select pg_temp.col($q$plone27_products$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_products$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_products$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_products$q$,$q$description$q$,$q$text$q$);
select pg_temp.col($q$plone27_products$q$,$q$status$q$,$q$text default 'draft'::text not null$q$);
select pg_temp.col($q$plone27_products$q$,$q$daily_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_products$q$,$q$credit_limit$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_products$q$,$q$monthly_fee$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_products$q$,$q$fee_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_products$q$,$q$interest_rate$q$,$q$numeric(9,4) default 0 not null$q$);
select pg_temp.col($q$plone27_products$q$,$q$min_age$q$,$q$integer$q$);
select pg_temp.col($q$plone27_products$q$,$q$requires_guardian$q$,$q$boolean default false not null$q$);
select pg_temp.col($q$plone27_products$q$,$q$valid_from$q$,$q$date$q$);
select pg_temp.col($q$plone27_products$q$,$q$valid_to$q$,$q$date$q$);
select pg_temp.col($q$plone27_products$q$,$q$terms$q$,$q$jsonb default '{}'::jsonb not null$q$);
select pg_temp.col($q$plone27_products$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_products$q$,$q$created_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_products$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$owner_user$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$wallet_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$week_start$q$,$q$date$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$status$q$,$q$text default 'available'::text not null$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$expires_on$q$,$q$date$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$claimed_at$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_rbu_bonuses$q$,$q$claimed_tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_reservations$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_reservations$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_reservations$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_reservations$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_reservations$q$,$q$status$q$,$q$text default 'active'::text$q$);
select pg_temp.col($q$plone27_reservations$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_sales$q$,$q$tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_sales$q$,$q$seller_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_sales$q$,$q$buyer_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_sales$q$,$q$base$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_sales$q$,$q$iva$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_sales$q$,$q$origin$q$,$q$text$q$);
select pg_temp.col($q$plone27_sales$q$,$q$created_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$from_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$to_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$run_at$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$recurrence$q$,$q$interval$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$status$q$,$q$text default 'active'::text$q$);
select pg_temp.col($q$plone27_scheduled$q$,$q$memo$q$,$q$text$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$key$q$,$q$text$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$new_value$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$old_value$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$proposed_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$status$q$,$q$text default 'pending'::text not null$q$);
select pg_temp.col($q$plone27_setting_changes$q$,$q$at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_settings$q$,$q$key$q$,$q$text$q$);
select pg_temp.col($q$plone27_settings$q$,$q$category$q$,$q$text$q$);
select pg_temp.col($q$plone27_settings$q$,$q$description$q$,$q$text$q$);
select pg_temp.col($q$plone27_settings$q$,$q$vtype$q$,$q$text$q$);
select pg_temp.col($q$plone27_settings$q$,$q$allowed$q$,$q$text[]$q$);
select pg_temp.col($q$plone27_settings$q$,$q$min_v$q$,$q$numeric$q$);
select pg_temp.col($q$plone27_settings$q$,$q$max_v$q$,$q$numeric$q$);
select pg_temp.col($q$plone27_settings$q$,$q$value$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_settings$q$,$q$sensitive$q$,$q$boolean default false not null$q$);
select pg_temp.col($q$plone27_settings$q$,$q$bank_overridable$q$,$q$boolean default true not null$q$);
select pg_temp.col($q$plone27_settings$q$,$q$version$q$,$q$integer default 1 not null$q$);
select pg_temp.col($q$plone27_settings$q$,$q$updated_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$period_from$q$,$q$date$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$period_to$q$,$q$date$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$evaluated$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$collected$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$pending$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_settlements$q$,$q$refunded$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_staff$q$,$q$user_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_staff$q$,$q$role$q$,$q$text$q$);
select pg_temp.col($q$plone27_staff$q$,$q$active$q$,$q$boolean default true not null$q$);
select pg_temp.col($q$plone27_staff$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_staff$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$product_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$status$q$,$q$text default 'past_due'::text not null$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$period_start$q$,$q$date$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$period_end$q$,$q$date default CURRENT_DATE not null$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$auto_renew$q$,$q$boolean default true not null$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$renewals$q$,$q$integer default 0 not null$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$last_tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_subscriptions$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$receipt_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$new_version_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$original_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$corrected_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$diff$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$status$q$,$q$text default 'simulated'::text$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$created_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$adj_receipt$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$adj_tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_adjustments$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_brackets$q$,$q$version_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_brackets$q$,$q$from_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_brackets$q$,$q$to_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_brackets$q$,$q$rate$q$,$q$numeric(9,4)$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$seq$q$,$q$bigint$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$subject_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$version_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$fingerprint$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$base$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$inputs$q$,$q$jsonb$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$prev_hash$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$hash$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$created_at$q$,$q$timestamp with time zone default now() not null$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$reemplaza$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_certificates$q$,$q$motivo$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_distribution$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_distribution$q$,$q$rule_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_distribution$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_distribution$q$,$q$pct$q$,$q$numeric(5,2)$q$);
select pg_temp.col($q$plone27_tax_distribution$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$event_key$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$rule_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$rule_version_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$pathway$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$base$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$status$q$,$q$text default 'calculated'::text not null$q$);
select pg_temp.col($q$plone27_tax_evaluations$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$rule_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$valid_from$q$,$q$date$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$valid_to$q$,$q$date$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$legal_basis$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_exemptions$q$,$q$approved_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$rule_version_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$account_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$base$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$status$q$,$q$text default 'issued'::text$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$due_date$q$,$q$date$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$original_receipt$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$evaluation_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$paid_tx$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$refunded$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$paid_amount$q$,$q$numeric(18,2) default 0 not null$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$disputed$q$,$q$boolean default false not null$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$obligor_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_receipts$q$,$q$operation_ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$rule_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$version$q$,$q$integer$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$method$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$rate$q$,$q$numeric(9,4)$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$min_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$max_amount$q$,$q$numeric(18,2)$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$valid_from$q$,$q$date$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$valid_to$q$,$q$date$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$status$q$,$q$text default 'draft'::text not null$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$reason$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$author$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$approver$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$published_at$q$,$q$timestamp with time zone$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$scope_bank$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$scope_op$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$retro_mode$q$,$q$text default 'prohibited'::text not null$q$);
select pg_temp.col($q$plone27_tax_rule_versions$q$,$q$fingerprint$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_rules$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_tax_rules$q$,$q$code$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_rules$q$,$q$name$q$,$q$text$q$);
select pg_temp.col($q$plone27_tax_rules$q$,$q$max_rate$q$,$q$numeric(9,4)$q$);
select pg_temp.col($q$plone27_tax_rules$q$,$q$collector_account$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$kind$q$,$q$text$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$status$q$,$q$text default 'posted'::text not null$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$idempotency_key$q$,$q$text$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$reverses$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$memo$q$,$q$text$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$created_by$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$created_at$q$,$q$timestamp with time zone default now()$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$transfer_ref$q$,$q$text$q$);
select pg_temp.col($q$plone27_transactions$q$,$q$req_hash$q$,$q$text$q$);
select pg_temp.col($q$plone27_webhooks$q$,$q$id$q$,$q$uuid default gen_random_uuid() not null$q$);
select pg_temp.col($q$plone27_webhooks$q$,$q$bank_id$q$,$q$uuid$q$);
select pg_temp.col($q$plone27_webhooks$q$,$q$url$q$,$q$text$q$);
select pg_temp.col($q$plone27_webhooks$q$,$q$secret$q$,$q$text$q$);
select pg_temp.col($q$plone27_webhooks$q$,$q$events$q$,$q$text[] default '{*}'::text[] not null$q$);
select pg_temp.col($q$plone27_webhooks$q$,$q$active$q$,$q$boolean default true not null$q$);
-- ===== 3. FUNCIONES (última versión de todas) =====
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_account_compat()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if new.kind='junior' and (new.allow_negative or new.credit_limit>0) then raise exception 'Una cuenta Junior no admite descubierto ni crédito'; end if; return new; end $function$
$q$, $q$función plone27_account_compat()$q$, $q$drop function if exists plone27_account_compat()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_accrue_interest(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare n int:=0; a record; i numeric; begin
  for a in select ac.id,p.interest_rate r,coalesce(bk.main_account,p.fee_account) fa,b.booked from plone27_accounts ac
    join plone27_products p on p.id=ac.product_id left join plone27_banks bk on bk.id=ac.bank_id join plone27_account_balances b on b.account_id=ac.id
    where p.kind='internal_credit' and p.interest_rate>0 and coalesce(bk.main_account,p.fee_account) is not null and ac.status='active' and b.booked<0 loop
    i:=round(-a.booked*a.r/100/12,2);
    if i>0 then begin perform plone27_post('int:'||a.id||':'||to_char(now(),'YYYY-MM'),'interest','Interés mensual',jsonb_build_array(
        jsonb_build_object('account',a.id,'dir','debit','amount',i),jsonb_build_object('account',a.fa,'dir','credit','amount',i)),p_actor); n:=n+1;
      exception when others then insert into plone27_incidents(kind,detail) values('interest_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end;
    end if;
  end loop; return n; end $function$
$q$, $q$función plone27_accrue_interest(uuid)$q$, $q$drop function if exists plone27_accrue_interest(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_active_version(p_code text, p_date date)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select v.id from plone27_tax_rule_versions v join plone27_tax_rules r on r.id=v.rule_id
  where r.code=p_code and v.status='published' and v.scope_bank is null and v.scope_op is null
    and p_date>=v.valid_from and (v.valid_to is null or p_date<=v.valid_to)
  order by v.valid_from desc,v.version desc limit 1 $function$
$q$, $q$función plone27_active_version(text,date)$q$, $q$drop function if exists plone27_active_version(text,date)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_activity_register(p_account uuid, p_category text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare aid uuid; begin
  if not exists(select 1 from plone27_accounts where id=p_account and kind in('business','personal') and status='active') then raise exception 'La actividad requiere una cuenta activa'; end if;
  insert into plone27_activities(account_id,category) values(p_account,p_category) returning id into aid;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'activity_register','activity',aid::text); return aid; end $function$
$q$, $q$función plone27_activity_register(uuid,text,uuid)$q$, $q$drop function if exists plone27_activity_register(uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_add_months(p_from date, p_months integer, p_anchor integer)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
AS $function$
declare base date; last_day int; begin
  base:=(p_from+make_interval(months=>p_months))::date;
  last_day:=extract(day from (date_trunc('month',base)+interval '1 month - 1 day'))::int;
  return make_date(extract(year from base)::int,extract(month from base)::int,least(p_anchor,last_day)); end $function$
$q$, $q$función plone27_add_months(date,integer,integer)$q$, $q$drop function if exists plone27_add_months(date,integer,integer)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_adjust_approve(p_adj uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare a plone27_tax_adjustments; begin
 select * into a from plone27_tax_adjustments where id=p_adj for update;
 if a.created_by is not distinct from p_actor and abs(a.diff)>=(plone27_setting('dual_approval_threshold')#>>'{}')::numeric then raise exception 'Doble aprobación: debe aprobar otra persona'; end if;
 update plone27_tax_adjustments set status='approved',approved_by=p_actor where id=p_adj and status='simulated'; end $function$
$q$, $q$función plone27_adjust_approve(uuid,uuid)$q$, $q$drop function if exists plone27_adjust_approve(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_adjust_execute(p_adj uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 update plone27_tax_adjustments set status='executed' where id=p_adj; return null; end $function$
$q$, $q$función plone27_adjust_execute(uuid,uuid)$q$, $q$drop function if exists plone27_adjust_execute(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_adjust_simulate(p_receipt uuid, p_version uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r plone27_tax_receipts; v plone27_tax_rule_versions; c numeric; aid uuid; begin
 select * into r from plone27_tax_receipts where id=p_receipt; select * into v from plone27_tax_rule_versions where id=p_version and status='published';
 if v.id is null or v.retro_mode='prohibited' then raise exception 'La regla no permite retroactividad'; end if;
 if r.created_at::date<v.valid_from or (v.valid_to is not null and r.created_at::date>v.valid_to) then raise exception 'Recibo fuera del ámbito de vigencia'; end if;
 c:=plone27_tax_calc(p_version,r.base);
 insert into plone27_tax_adjustments(receipt_id,new_version_id,original_amount,corrected_amount,diff,created_by) values(p_receipt,p_version,r.amount,c,c-r.amount,p_actor) returning plone27_tax_adjustments.id into aid; return aid; end $function$
$q$, $q$función plone27_adjust_simulate(uuid,uuid,uuid)$q$, $q$drop function if exists plone27_adjust_simulate(uuid,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_apply_late_penalties(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int:=0; r record; pol jsonb; amt numeric; begin
 if not (plone27_setting('late_penalty_enabled'))::boolean then return 0; end if;
 for r in select t.id,t.ref,t.account_id,t.amount,t.paid_amount,t.due_date,ru.collector_account col from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id
  where t.status in('issued','partial') and not t.disputed and t.original_receipt is null and not exists(select 1 from plone27_debts d where d.origin='penalty:'||t.id) loop
  pol:=plone27_policy_resolve('penalty',r.account_id); continue when pol is null or r.due_date+coalesce((pol->>'grace_days')::int,0)>=current_date;
  amt:=case pol->>'type' when 'percent' then round((r.amount-r.paid_amount)*(pol->>'value')::numeric/100,2) else (pol->>'value')::numeric end;
  if pol ? 'max_amount' then amt:=least(amt,(pol->>'max_amount')::numeric); end if;
  if amt>0 then insert into plone27_debts(account_id,creditor_account,principal,due_date,reason,authorized_by,origin) values(r.account_id,r.col,amt,current_date+30,'Recargo por mora del recibo '||r.ref,(pol->>'approved_by')::uuid,'penalty:'||r.id); n:=n+1; end if; end loop; return n; end $function$
$q$, $q$función plone27_apply_late_penalties(uuid)$q$, $q$drop function if exists plone27_apply_late_penalties(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_approval_decide(p_id uuid, p_approve boolean, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
 if exists(select 1 from plone27_approvals where id=p_id and requested_by is not distinct from p_actor) then raise exception 'El solicitante no puede aprobar su propia solicitud'; end if;
 update plone27_approvals set approved_by=p_actor,result=case when p_approve then 'approved' else 'rejected' end where id=p_id and result is null; end $function$
$q$, $q$función plone27_approval_decide(uuid,boolean,uuid)$q$, $q$drop function if exists plone27_approval_decide(uuid,boolean,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_approval_request(p_subject text, p_subject_id uuid, p_reason text, p_actor uuid)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ insert into plone27_approvals(subject,subject_id,requested_by,reason) values(p_subject,p_subject_id,p_actor,p_reason) returning id $function$
$q$, $q$función plone27_approval_request(text,uuid,text,uuid)$q$, $q$drop function if exists plone27_approval_request(text,uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_autocollect_debts(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int:=0; begin
  if not (plone27_setting('autocobro_habilitado'))::boolean then return 0; end if;
  for r in select d.id,d.account_id,d.creditor_account,d.principal+d.authorized_charges-d.paid pend from plone27_debts d
    where not d.disputed and d.paid<d.principal+d.authorized_charges and d.due_date<=current_date and d.creditor_account is not null order by d.due_date,d.id loop
    continue when not plone27_collectable(r.account_id,r.pend);
    begin perform plone27_debt_pay('auto:debt:'||r.id||':'||r.pend,r.id,r.pend,p_actor); n:=n+1;
    exception when others then insert into plone27_incidents(kind,detail) values('autocobro_fallido',jsonb_build_object('deuda',r.id,'err',sqlerrm)); end;
  end loop; return n; end $function$
$q$, $q$función plone27_autocollect_debts(uuid)$q$, $q$drop function if exists plone27_autocollect_debts(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_autocollect_taxes(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; n int:=0; begin
  if not (plone27_setting('autocobro_habilitado'))::boolean then return 0; end if;
  for r in select t.id,t.account_id,t.amount-t.paid_amount pend from plone27_tax_receipts t
    where t.status in('issued','partial') and not t.disputed and t.due_date<=current_date and t.amount-t.paid_amount>0 order by t.due_date,t.id loop
    continue when not plone27_collectable(r.account_id,r.pend);
    begin perform plone27_tax_pay_partial('auto:tax:'||r.id||':'||r.pend,r.id,r.pend,p_actor); n:=n+1;
    exception when others then insert into plone27_incidents(kind,detail) values('autocobro_fallido',jsonb_build_object('recibo',r.id,'err',sqlerrm)); end;
  end loop; return n; end $function$
$q$, $q$función plone27_autocollect_taxes(uuid)$q$, $q$drop function if exists plone27_autocollect_taxes(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_available(p_acc uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$ select booked-reserved from plone27_account_balances where account_id=p_acc $function$
$q$, $q$función plone27_available(uuid)$q$, $q$drop function if exists plone27_available(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_bank_accounts_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
  if new.main_account is not null and not exists(select 1 from plone27_accounts a where a.id=new.main_account and a.bank_id=new.id)
    then raise exception 'La cuenta principal debe pertenecer a la propia entidad'; end if;
  if new.tax_account is not null and not exists(select 1 from plone27_accounts a where a.id=new.tax_account and a.bank_id=new.id)
    then raise exception 'La cuenta de impuestos debe pertenecer a la propia entidad'; end if;
  return new; end $function$
$q$, $q$función plone27_bank_accounts_guard()$q$, $q$drop function if exists plone27_bank_accounts_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_bank_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if new.status is distinct from old.status then
  if (old.status,new.status) not in(('draft','review'),('review','draft'),('review','active'),('active','suspended'),('suspended','active'),('active','closed'),('suspended','closed'))
   then raise exception 'Transición % → % no permitida',old.status,new.status; end if;
  if new.status='active' and new.approved_by is null then raise exception 'Activar requiere aprobación registrada'; end if; end if; return new; end $function$
$q$, $q$función plone27_bank_guard()$q$, $q$drop function if exists plone27_bank_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_bank_set_accounts(p_bank uuid, p_main uuid, p_tax uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  update plone27_banks set main_account=p_main,tax_account=p_tax where id=p_bank;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'bank_accounts','bank',p_bank::text,jsonb_build_object('main',p_main,'tax',p_tax));
end $function$
$q$, $q$función plone27_bank_set_accounts(uuid,uuid,uuid,uuid)$q$, $q$drop function if exists plone27_bank_set_accounts(uuid,uuid,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_bank_visible(p_bank uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select exists(select 1 from plone27_staff s where s.user_id=auth.uid() and s.active and (s.bank_id is null or s.bank_id=p_bank)) $function$
$q$, $q$función plone27_bank_visible(uuid)$q$, $q$drop function if exists plone27_bank_visible(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_bracket_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare vid uuid; begin
  vid:=case when tg_op='DELETE' then old.version_id else new.version_id end;
  if exists(select 1 from plone27_tax_rule_versions v where v.id=vid and v.status='published') then raise exception 'Tramos de una versión publicada: inmutables'; end if;
  if tg_op='DELETE' then return old; end if; return new; end $function$
$q$, $q$función plone27_bracket_guard()$q$, $q$drop function if exists plone27_bracket_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_bracket_rate(p_version uuid, p_value numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
  select b.rate from plone27_tax_brackets b where b.version_id=p_version and p_value>b.from_amount and (b.to_amount is null or p_value<=b.to_amount) limit 1 $function$
$q$, $q$función plone27_bracket_rate(uuid,numeric)$q$, $q$drop function if exists plone27_bracket_rate(uuid,numeric)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_card_authorize(p_card uuid, p_amount numeric, p_merchant uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c plone27_cards; res uuid; ch uuid; begin
 select * into c from plone27_cards where id=p_card for update; if c.status<>'active' then raise exception 'Tarjeta no activa'; end if;
 if c.kind='credit' then
  if coalesce((select sum(amount) from plone27_card_charges where card_id=p_card and status in('authorized','billed')),0)+p_amount>coalesce(c.credit_limit,0) then raise exception 'Límite de crédito superado'; end if;
 else if plone27_available(c.account_id)<p_amount then raise exception 'Saldo insuficiente'; end if;
  insert into plone27_reservations(account_id,amount,reason) values(c.account_id,p_amount,'card auth') returning id into res; end if;
 insert into plone27_card_charges(card_id,merchant_account,amount,reservation_id) values(p_card,p_merchant,p_amount,res) returning id into ch; return ch; end $function$
$q$, $q$función plone27_card_authorize(uuid,numeric,uuid,uuid)$q$, $q$drop function if exists plone27_card_authorize(uuid,numeric,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_card_close_cycle(p_key text, p_card uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c plone27_cards; lines jsonb; tot numeric; begin
 select * into c from plone27_cards where id=p_card for update;
 select sum(amount) into tot from plone27_card_charges where card_id=p_card and status='billed'; if coalesce(tot,0)=0 then return null; end if;
 select jsonb_build_array(jsonb_build_object('account',c.account_id,'dir','debit','amount',tot))||jsonb_agg(jsonb_build_object('account',m,'dir','credit','amount',s)) into lines
  from(select merchant_account m,sum(amount) s from plone27_card_charges where card_id=p_card and status='billed' group by 1)q;
 update plone27_card_charges set status='settled' where card_id=p_card and status='billed';
 return plone27_post(p_key,'credit_cycle',null,lines,p_actor); end $function$
$q$, $q$función plone27_card_close_cycle(text,uuid,uuid)$q$, $q$drop function if exists plone27_card_close_cycle(text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_card_compat()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare a plone27_accounts; j plone27_junior_profiles; begin
 select * into a from plone27_accounts where id=new.account_id; if a.kind<>'junior' then return new; end if;
 if new.kind='credit' then raise exception 'Una cuenta Junior no admite tarjeta de crédito'; end if;
 select * into j from plone27_junior_profiles where customer_id=a.customer_id; if j.customer_id is not null and not j.card_enabled then raise exception 'El control parental no permite tarjetas'; end if; return new; end $function$
$q$, $q$función plone27_card_compat()$q$, $q$drop function if exists plone27_card_compat()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_card_order_step(p_card uuid, p_to text, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare o text; begin
 if p_to='ordered' then insert into plone27_card_orders(card_id) values(p_card); update plone27_cards set status='suspended' where id=p_card; return; end if;
 select status into o from plone27_card_orders where card_id=p_card for update;
 if (o,p_to) not in(('ordered','produced'),('produced','shipped'),('shipped','activated'),('ordered','cancelled'),('produced','cancelled')) then raise exception 'Transición de pedido no permitida'; end if;
 update plone27_card_orders set status=p_to,updated_at=now() where card_id=p_card; if p_to='activated' then update plone27_cards set status='active' where id=p_card; end if; end $function$
$q$, $q$función plone27_card_order_step(uuid,text,uuid)$q$, $q$drop function if exists plone27_card_order_step(uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_card_renew(p_card uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare c plone27_cards; begin
 select * into c from plone27_cards where id=p_card; perform plone27_card_set_status(p_card,'closed',p_actor);
 return plone27_issue_card(c.account_id,c.kind,c.design_id,c.credit_limit,c.is_test,p_actor); end $function$
$q$, $q$función plone27_card_renew(uuid,uuid)$q$, $q$drop function if exists plone27_card_renew(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_card_set_status(p_card uuid, p_to text, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare o text; begin
 select status into o from plone27_cards where id=p_card for update; if o='closed' then raise exception 'Tarjeta cancelada'; end if;
 update plone27_cards set status=p_to where id=p_card; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'card_status','card',p_card::text,to_jsonb(p_to)); end $function$
$q$, $q$función plone27_card_set_status(uuid,text,uuid)$q$, $q$drop function if exists plone27_card_set_status(uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_card_settle(p_key text, p_charge uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ch plone27_card_charges; c plone27_cards; tx uuid; begin
 select * into ch from plone27_card_charges where id=p_charge for update; if ch.status<>'authorized' then raise exception 'Cargo ya procesado'; end if;
 select * into c from plone27_cards where id=ch.card_id;
 if c.kind='credit' then update plone27_card_charges set status='billed' where id=p_charge; return null; end if;  -- crédito: consumo ≠ liquidación
 update plone27_reservations set status='released' where id=ch.reservation_id;
 tx:=plone27_transfer(p_key,c.account_id,ch.merchant_account,ch.amount,'Tarjeta',p_actor); update plone27_card_charges set status='settled' where id=p_charge; return tx; end $function$
$q$, $q$función plone27_card_settle(text,uuid,uuid)$q$, $q$drop function if exists plone27_card_settle(text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_cash_forecast(p_days integer, p_actor uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select jsonb_build_object('horizon_days',p_days,
  'scheduled_out',coalesce((select sum(amount) from plone27_scheduled where status='active' and run_at<=now()+make_interval(days=>p_days)),0),
  'tax_due',coalesce((select sum(amount) from plone27_tax_receipts where status='issued' and due_date<=current_date+p_days),0),
  'grants_pending',coalesce((select sum(amount) from plone27_justifications where status='approved'),0)) $function$
$q$, $q$función plone27_cash_forecast(integer,uuid)$q$, $q$drop function if exists plone27_cash_forecast(integer,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_cert_append(p_kind text, p_subject uuid, p_version uuid, p_base numeric, p_amount numeric, p_inputs jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  return plone27_cert_insert(p_kind,p_subject,p_version,p_base,p_amount,p_inputs,null,null); end $function$
$q$, $q$función plone27_cert_append(text,uuid,uuid,numeric,numeric,jsonb)$q$, $q$drop function if exists plone27_cert_append(text,uuid,uuid,numeric,numeric,jsonb)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_cert_insert(p_kind text, p_subject uuid, p_version uuid, p_base numeric, p_amount numeric, p_inputs jsonb, p_reemplaza uuid, p_motivo text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare prev text; fp text; bt text:=p_base::numeric(18,2)::text; am text:=p_amount::numeric(18,2)::text; h text; cid uuid; begin
  perform pg_advisory_xact_lock(hashtext('plone27_cert'));
  select hash into prev from plone27_tax_certificates order by seq desc limit 1; prev:=coalesce(prev,'GENESIS');
  fp:=(select fingerprint from plone27_tax_rule_versions where id=p_version);
  h:=encode(sha256(convert_to(plone27_cert_text(prev,p_kind,p_subject,p_version,fp,bt,am,p_inputs),'utf8')),'hex');
  insert into plone27_tax_certificates(kind,subject_id,version_id,fingerprint,base,amount,inputs,prev_hash,hash,reemplaza,motivo)
    values(p_kind,p_subject,p_version,fp,p_base,p_amount,p_inputs,prev,h,p_reemplaza,p_motivo) returning id into cid;
  return cid; end $function$
$q$, $q$función plone27_cert_insert(text,uuid,uuid,numeric,numeric,jsonb,uuid,text)$q$, $q$drop function if exists plone27_cert_insert(text,uuid,uuid,numeric,numeric,jsonb,uuid,text)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_cert_receipt()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare kind text; begin
  kind:=case when new.amount=plone27_tax_calc(new.rule_version_id,new.base) then 'recibo' else 'regularizacion' end;
  perform plone27_cert_append(kind,new.id,new.rule_version_id,new.base,new.amount,
    jsonb_build_object('tramos',plone27_tax_trace(new.rule_version_id,new.base),'cuenta',new.account_id,'obligado',new.obligor_account,'operacion',new.operation_ref));
  return null; end $function$
$q$, $q$función plone27_cert_receipt()$q$, $q$drop function if exists plone27_cert_receipt()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_cert_receipt_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare prevc uuid; begin
  select id into prevc from plone27_tax_certificates where subject_id=new.id order by seq desc limit 1;
  perform plone27_cert_insert('rectificacion',new.id,new.rule_version_id,new.base,new.amount,
    jsonb_build_object('tramos',plone27_tax_trace(new.rule_version_id,new.base),'cuenta',new.account_id,'obligado',new.obligor_account,
      'operacion',new.operation_ref,'importe_anterior',old.amount::text,'base_anterior',old.base::text),
    prevc,'Modificación del recibo: certificado nuevo; el certificado anterior no se altera');
  return null; end $function$
$q$, $q$función plone27_cert_receipt_update()$q$, $q$drop function if exists plone27_cert_receipt_update()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_cert_text(p_prev text, p_kind text, p_subject uuid, p_version uuid, p_fp text, p_base text, p_amount text, p_inputs jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$ select p_prev||'|'||p_kind||'|'||p_subject::text||'|'||coalesce(p_version::text,'-')||'|'||coalesce(p_fp,'-')||'|'||p_base||'|'||p_amount||'|'||p_inputs::text $function$
$q$, $q$función plone27_cert_text(text,text,uuid,uuid,text,text,text,jsonb)$q$, $q$drop function if exists plone27_cert_text(text,text,uuid,uuid,text,text,text,jsonb)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_certification_report()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  select count(*) into alterados from plone27_tax_receipts r
    join lateral (select k.amount,k.base from plone27_tax_certificates k where k.subject_id=r.id order by k.seq desc limit 1) u on true
    where r.amount<>u.amount or r.base<>u.base;
  select count(*) into sin from plone27_tax_receipts r where not exists(select 1 from plone27_tax_certificates k where k.subject_id=r.id);
  return jsonb_build_object('certificados',total,'cadena_rota',rota,'importes_no_recalculan',disc,'importes_sin_certificado_vigente',alterados,
    'huella_norma_discrepante',fpd,'recibos_sin_certificado',sin,'certificados_informativos',reg,
    'estado',case when rota+disc+alterados+fpd+sin=0 then 'OK' else 'REVISAR' end);
end $function$
$q$, $q$función plone27_certification_report()$q$, $q$drop function if exists plone27_certification_report()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_certification_report(p_actor uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select plone27_certification_report() $function$
$q$, $q$función plone27_certification_report(uuid)$q$, $q$drop function if exists plone27_certification_report(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_charge_product_fees(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare n int:=0; a record; begin
 for a in select ac.id,p.monthly_fee fee,p.fee_account from plone27_accounts ac join plone27_products p on p.id=ac.product_id where ac.status='active' and p.monthly_fee>0 and p.fee_account is not null loop
  begin perform plone27_transfer('pfee:'||a.id||':'||to_char(now(),'YYYY-MM'),a.id,a.fee_account,a.fee,'Cuota de producto',p_actor); n:=n+1;
  exception when others then insert into plone27_incidents(kind,detail) values('product_fee_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end; end loop; return n; end $function$
$q$, $q$función plone27_charge_product_fees(uuid)$q$, $q$drop function if exists plone27_charge_product_fees(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_collectable(p_account uuid, p_amount numeric)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from plone27_accounts a where a.id=p_account and a.status='active' and a.collectable) and plone27_available(p_account)>=p_amount $function$
$q$, $q$función plone27_collectable(uuid,numeric)$q$, $q$drop function if exists plone27_collectable(uuid,numeric)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_config_set(p_key text, p_account uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  if p_key not in('cuenta_tributos','cuenta_rbu_origen') then raise exception 'Clave no permitida: %',p_key; end if;
  if not plone27_es_institucional(p_account) then raise exception 'La cuenta debe ser institucional'; end if;
  insert into plone27_config(key,value) values(p_key,p_account::text) on conflict(key) do update set value=excluded.value;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'config_set','config',p_key,jsonb_build_object('cuenta',p_account));
end $function$
$q$, $q$función plone27_config_set(text,uuid,uuid)$q$, $q$drop function if exists plone27_config_set(text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_contract_create(p_employer uuid, p_worker uuid, p_worker_user uuid, p_gross numeric, p_start date, p_pay_day integer, p_approved_by uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare bk uuid; pd int; first_pay date; cid uuid; begin
  if p_approved_by is null then raise exception 'El contrato exige aprobación registrada'; end if;
  select bank_id into bk from plone27_accounts where id=p_employer; if bk is null then raise exception 'Cuenta empleadora inexistente'; end if;
  pd:=coalesce(p_pay_day,(plone27_setting('dia_nomina',bk)#>>'{}')::int);
  first_pay:=plone27_add_months(p_start,0,pd); if first_pay<p_start then first_pay:=plone27_add_months(p_start,1,pd); end if;
  insert into plone27_contracts(bank_id,employer_account,worker_account,worker_user,gross_monthly,start_date,pay_day,next_pay,approved_by)
    values(bk,p_employer,p_worker,p_worker_user,p_gross,p_start,pd,first_pay,p_approved_by) returning id into cid;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'contract_create','contract',cid::text);
  return cid; end $function$
$q$, $q$función plone27_contract_create(uuid,uuid,uuid,numeric,date,integer,uuid,uuid)$q$, $q$drop function if exists plone27_contract_create(uuid,uuid,uuid,numeric,date,integer,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_contract_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare smi numeric; ek text; wk text; begin
  select kind into ek from plone27_accounts where id=new.employer_account and bank_id=new.bank_id;
  select kind into wk from plone27_accounts where id=new.worker_account and bank_id=new.bank_id;
  if ek is distinct from 'business' then raise exception 'La cuenta empleadora debe ser de empresa de la entidad'; end if;
  if wk is distinct from 'personal' then raise exception 'La cuenta del trabajador debe ser personal de la entidad'; end if;
  smi:=(plone27_setting('smi_mensual_completa_pz',new.bank_id)#>>'{}')::numeric;
  if new.gross_monthly<smi then raise exception 'Contrato no válido: el bruto mensual está por debajo del SMI (% Pz al mes)',smi; end if;
  return new; end $function$
$q$, $q$función plone27_contract_guard()$q$, $q$drop function if exists plone27_contract_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_credit_floor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a plone27_accounts; k text; bal numeric; begin
 if new.direction<>'debit' then return new; end if; select * into a from plone27_accounts where id=new.account_id;
 if a.kind='system' or not a.allow_negative then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','interest') then return new; end if;
 select coalesce(sum(case when direction='credit' then amount else -amount end),0) into bal from plone27_ledger_entries where account_id=new.account_id;
 if bal-new.amount < -a.credit_limit then raise exception 'Límite de crédito superado'; end if; return new; end $function$
$q$, $q$función plone27_credit_floor()$q$, $q$drop function if exists plone27_credit_floor()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_debt_pay(p_key text, p_debt uuid, p_amount numeric, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare d plone27_debts; tx uuid; begin
 select * into d from plone27_debts where id=p_debt for update; if d.disputed then raise exception 'Deuda en disputa: no se cobra'; end if;
 if d.paid+p_amount>d.principal+d.authorized_charges then raise exception 'Excede la deuda'; end if;
 tx:=plone27_transfer(p_key,d.account_id,d.creditor_account,p_amount,'Deuda '||d.ref,p_actor); update plone27_debts set paid=paid+p_amount where id=p_debt; return tx; end $function$
$q$, $q$función plone27_debt_pay(text,uuid,numeric,uuid)$q$, $q$drop function if exists plone27_debt_pay(text,uuid,numeric,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_debt_terms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare pol jsonb; begin
 if new.account_id is null then return new; end if; pol:=plone27_policy_resolve('debt_terms',new.account_id); if pol is null then return new; end if;
 if tg_op='INSERT' and pol->>'max_principal' is not null and new.principal>(pol->>'max_principal')::numeric then raise exception 'Supera el principal máximo de la norma (%)',pol->>'max_principal'; end if;
 if tg_op='UPDATE' and new.paid>old.paid and pol->>'allow_partial'='false' and new.paid<new.principal+new.authorized_charges then raise exception 'La norma no permite pagos parciales'; end if; return new; end $function$
$q$, $q$función plone27_debt_terms()$q$, $q$drop function if exists plone27_debt_terms()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_design_buy(p_key text, p_design uuid, p_account uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d plone27_card_designs; tx uuid; t numeric; begin
 select * into d from plone27_card_designs where id=p_design; if d.status<>'approved' then raise exception 'Diseño no aprobado'; end if;
 t:=d.price+d.license_fee; if t>0 then tx:=plone27_transfer(p_key,p_account,d.revenue_account,t,'Diseño '||d.name,p_actor); end if;
 insert into plone27_design_purchases values(p_design,p_account,tx) on conflict do nothing; return tx; end $function$
$q$, $q$función plone27_design_buy(text,uuid,uuid,uuid)$q$, $q$drop function if exists plone27_design_buy(text,uuid,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_design_step(p_design uuid, p_to text, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare o text; begin
 select status into o from plone27_card_designs where id=p_design for update;
 if (o,p_to) not in(('draft','submitted'),('submitted','review'),('review','approved'),('review','rejected'),('rejected','draft')) then raise exception 'Transición no permitida'; end if;
 update plone27_card_designs set status=p_to where id=p_design; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'design_step','design',p_design::text,to_jsonb(p_to)); end $function$
$q$, $q$función plone27_design_step(uuid,text,uuid)$q$, $q$drop function if exists plone27_design_step(uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_dispute_open(p_type text, p_subject uuid, p_reason text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare acc uuid; pol jsonb; did uuid; begin
 if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 if p_type='receipt' then select account_id into acc from plone27_tax_receipts where id=p_subject; else select account_id into acc from plone27_debts where id=p_subject; end if;
 if acc is null then raise exception 'Objeto inexistente'; end if;
 pol:=plone27_policy_resolve('dispute',acc);
 insert into plone27_disputes(subject_type,subject_id,account_id,reason,opened_by,due_at) values(p_type,p_subject,acc,p_reason,p_actor,now()+make_interval(days=>coalesce((pol->>'max_days')::int,30))) returning plone27_disputes.id into did;
 if p_type='receipt' then update plone27_tax_receipts set disputed=true where id=p_subject; else update plone27_debts set disputed=true where id=p_subject; end if; return did; end $function$
$q$, $q$función plone27_dispute_open(text,uuid,text,uuid)$q$, $q$drop function if exists plone27_dispute_open(text,uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_dispute_resolve(p_id uuid, p_outcome text, p_note text, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare d plone27_disputes; begin
 if p_outcome not in('upheld','rejected','withdrawn') then raise exception 'Resultado no válido'; end if;
 select * into d from plone27_disputes where id=p_id and status='open' for update; if d.id is null then raise exception 'Disputa no abierta'; end if;
 if p_outcome<>'withdrawn' and d.opened_by is not distinct from p_actor then raise exception 'La disputa debe resolverla otra persona'; end if;
 if d.subject_type='receipt' then update plone27_tax_receipts set disputed=false,status=case when p_outcome='upheld' then 'rectified' else status end where id=d.subject_id;
 else update plone27_debts set disputed=false,authorized_charges=case when p_outcome='upheld' then 0 else authorized_charges end,principal=case when p_outcome='upheld' then paid else principal end where id=d.subject_id; end if;
 update plone27_disputes set status=p_outcome,resolution=p_note,resolved_by=p_actor,resolved_at=now() where id=p_id;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'dispute_resolved','dispute',p_id::text,jsonb_build_object('outcome',p_outcome)); end $function$
$q$, $q$función plone27_dispute_resolve(uuid,text,text,uuid)$q$, $q$drop function if exists plone27_dispute_resolve(uuid,text,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_dist_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if (select coalesce(sum(pct),0) from plone27_tax_distribution where rule_id=new.rule_id and id<>new.id)+new.pct>100 then raise exception 'La distribución supera el 100%%'; end if; return new; end $function$
$q$, $q$función plone27_dist_guard()$q$, $q$drop function if exists plone27_dist_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_emit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare b uuid[]; p jsonb; begin
 if new.action='post' then
  select array_agg(distinct a.bank_id) into b from plone27_accounts a where a.id in(select (x->>'account')::uuid from jsonb_array_elements(new.detail) x);
  select jsonb_build_object('operation',t.ref,'transfer',t.transfer_ref,'kind',t.kind) into p from plone27_transactions t where t.id=new.entity_id::uuid;
  insert into plone27_outbox(event,bank_ids,payload) values('transaction.posted',coalesce(b,'{}'),p); end if; return new; end $function$
$q$, $q$función plone27_emit()$q$, $q$drop function if exists plone27_emit()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_es_institucional(p_acc uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from plone27_accounts a join plone27_banks b on b.id=a.bank_id where a.id=p_acc and b.code='0000')
      or exists(select 1 from plone27_banks b where b.main_account=p_acc or b.tax_account=p_acc)
      or exists(select 1 from plone27_institutional_accounts i where i.account_id=p_acc) $function$
$q$, $q$función plone27_es_institucional(uuid)$q$, $q$drop function if exists plone27_es_institucional(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_fee_cap()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
  if new.method='percent' and new.rate>(plone27_setting('tasas_transferencia_max_pct')#>>'{}')::numeric
    then raise exception 'La tasa de transferencia supera el tope central (Art. 4.3)'; end if;
  return new; end $function$
$q$, $q$función plone27_fee_cap()$q$, $q$drop function if exists plone27_fee_cap()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_finanzas_daily(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
$q$, $q$función plone27_finanzas_daily(uuid)$q$, $q$drop function if exists plone27_finanzas_daily(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_has_role(r text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select exists(select 1 from plone27_staff where user_id=auth.uid() and active and (role=any(r) or role='admin')) $function$
$q$, $q$función plone27_has_role(text[])$q$, $q$drop function if exists plone27_has_role(text[])$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iaep_monthly(p_period date, p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  end loop; return n; end $function$
$q$, $q$función plone27_iaep_monthly(date,uuid)$q$, $q$drop function if exists plone27_iaep_monthly(date,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iban_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if tg_op='INSERT' then
  if new.iban is null or new.iban !~ '^PZ-[0-9]{4}-[0-9]{4}$' or substr(new.iban,4,4) is distinct from (select code from plone27_banks where id=new.bank_id) then raise exception 'IBAN solo generado por servidor'; end if;
 elsif new.iban is distinct from old.iban or new.bank_id is distinct from old.bank_id then raise exception 'IBAN inmutable'; end if; return new; end $function$
$q$, $q$función plone27_iban_guard()$q$, $q$drop function if exists plone27_iban_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin raise exception 'Registro contable inmutable: usa reversión'; end $function$
$q$, $q$función plone27_immutable()$q$, $q$drop function if exists plone27_immutable()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_institutional_set(p_account uuid, p_motivo text, p_junior boolean, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  if not exists(select 1 from plone27_accounts where id=p_account) then raise exception 'Cuenta inexistente'; end if;
  insert into plone27_institutional_accounts(account_id,motivo,puede_operar_junior,aprobado_por) values(p_account,p_motivo,coalesce(p_junior,false),p_actor)
    on conflict(account_id) do update set motivo=excluded.motivo,puede_operar_junior=excluded.puede_operar_junior,aprobado_por=excluded.aprobado_por;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'institutional_set','account',p_account::text,jsonb_build_object('junior',p_junior,'motivo',p_motivo));
end $function$
$q$, $q$función plone27_institutional_set(uuid,text,boolean,uuid)$q$, $q$drop function if exists plone27_institutional_set(uuid,text,boolean,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_integrity_report()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  union all select 'Eventos de webhook fallidos','warning',count(*),'' from plone27_outbox where status='failed') q $function$
$q$, $q$función plone27_integrity_report()$q$, $q$drop function if exists plone27_integrity_report()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_issue_card(p_account uuid, p_kind text, p_design uuid, p_limit numeric, p_test boolean, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r text; num text; cid uuid; begin
 if not exists(select 1 from plone27_accounts where id=p_account and status='active') then raise exception 'Cuenta no activa'; end if;
 if p_design is not null and not exists(select 1 from plone27_design_purchases where design_id=p_design and account_id=p_account) then raise exception 'Diseño no adquirido'; end if;
 r:=plone27_next_id('TAR');
 if p_test then num:=lpad(floor(random()*10000000000000000)::bigint::text,16,'0'); end if;
 insert into plone27_cards(account_id,kind,design_id,credit_limit,card_ref,is_test,expires,last4,pan_hash)
  values(p_account,p_kind,p_design,p_limit,r,p_test,current_date+interval '5 years',right(num,4),encode(sha256(convert_to(coalesce(num,r),'utf8')),'hex')) returning plone27_cards.id into cid;
 return jsonb_build_object('id',cid,'card_ref',r,'test_number',regexp_replace(num,'(\d{4})(?=\d)','\1 ','g')); end $function$
$q$, $q$función plone27_issue_card(uuid,text,uuid,numeric,boolean,uuid)$q$, $q$drop function if exists plone27_issue_card(uuid,text,uuid,numeric,boolean,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iva_approve(p_finding uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  return rid; end $function$
$q$, $q$función plone27_iva_approve(uuid,uuid)$q$, $q$drop function if exists plone27_iva_approve(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iva_propose(p_finding uuid, p_accion text, p_motivo text, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  if p_accion not in('regularizar','descartar') then raise exception 'Acción no válida'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'Motivo obligatorio (mín. 10 caracteres)'; end if;
  update plone27_iva_findings set propuesta_accion=p_accion,motivo=p_motivo,propuesto_por=p_actor where id=p_finding and status='abierto';
  if not found then raise exception 'Hallazgo no abierto'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'iva_propose','finding',p_finding::text,jsonb_build_object('accion',p_accion,'motivo',p_motivo));
end $function$
$q$, $q$función plone27_iva_propose(uuid,text,text,uuid)$q$, $q$drop function if exists plone27_iva_propose(uuid,text,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iva_report(p_desde date, p_hasta date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'iva_regularizado',(select coalesce(sum(iva),0) from plone27_sales where origin='regularizada' and created_at::date between p_desde and p_hasta)) $function$
$q$, $q$función plone27_iva_report(date,date)$q$, $q$drop function if exists plone27_iva_report(date,date)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iva_report(p_desde date, p_hasta date, p_actor uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select plone27_iva_report(p_desde,p_hasta) $function$
$q$, $q$función plone27_iva_report(date,date,uuid)$q$, $q$drop function if exists plone27_iva_report(date,date,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iva_scan(p_desde timestamp with time zone, p_hasta timestamp with time zone, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
$q$, $q$función plone27_iva_scan(timestamp with time zone,timestamp with time zone,uuid)$q$, $q$drop function if exists plone27_iva_scan(timestamp with time zone,timestamp with time zone,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_iva_split(p_total numeric)
 RETURNS TABLE(base numeric, iva numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare vid uuid; tasa numeric; begin
  vid:=plone27_active_version('IVA',current_date);
  if vid is null then base:=p_total; iva:=null; return next; return; end if;
  select rate into tasa from plone27_tax_rule_versions where id=vid;
  if (plone27_setting('iva_criterio')#>>'{}')='inclusivo' then base:=round(p_total*100/(100+tasa),2); iva:=p_total-base;
  else base:=p_total; iva:=plone27_tax_calc(vid,p_total); end if;
  return next; end $function$
$q$, $q$función plone27_iva_split(numeric)$q$, $q$drop function if exists plone27_iva_split(numeric)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_junior_counterparty()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  if exists(select 1 from (select distinct n.transaction_id from new_rows n join plone27_transactions t on t.id=n.transaction_id where t.kind<>'reversal') x
    where exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id where e.transaction_id=x.transaction_id and a.kind='junior')
      and exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
                 where e.transaction_id=x.transaction_id and a.kind in('personal','shared','business')
                   and not exists(select 1 from plone27_institutional_accounts i where i.account_id=a.id and i.puede_operar_junior)))
  then raise exception 'Cuenta Junior: no puede enviar ni recibir de cuentas de clientes habituales'; end if;
  return null; end $function$
$q$, $q$función plone27_junior_counterparty()$q$, $q$drop function if exists plone27_junior_counterparty()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_junior_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 if j.monthly_limit is not null and um+new.amount>j.monthly_limit then raise exception 'Control parental: supera el límite mensual (% Pz)',j.monthly_limit; end if; return new; end $function$
$q$, $q$función plone27_junior_profile()$q$, $q$drop function if exists plone27_junior_profile()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_junior_tax_payer()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare acc uuid; begin
  if (plone27_setting('capitalia_asume_impuestos_junior')#>>'{}')::boolean then
    select bk.main_account into acc from plone27_config c join plone27_banks bk on bk.id=nullif(c.value,'')::uuid where c.key='entidad_capitalia';
    if acc is null then raise exception 'Capitalia no tiene cuenta principal configurada'; end if;
  else
    select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_placeta_junior';
    if acc is null then raise exception 'Falta la cuenta de Placeta Junior (seed 0011)'; end if;
  end if;
  return acc; end $function$
$q$, $q$función plone27_junior_tax_payer()$q$, $q$drop function if exists plone27_junior_tax_payer()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_justify(p_grant uuid, p_tx uuid, p_invoice text, p_amount numeric, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g plone27_grants; spent numeric; jid uuid; begin
 select * into g from plone27_grants where id=p_grant for update;
 select sum(e.amount) into spent from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.transaction_id=p_tx and e.account_id=g.beneficiary_account and e.direction='debit' and t.status='posted';
 if coalesce(spent,0)<p_amount then raise exception 'Transacción no elegible o importe excesivo'; end if;
 if coalesce((select sum(amount) from plone27_justifications where grant_id=p_grant and status<>'rejected'),0)+p_amount>g.granted then raise exception 'Supera lo concedido'; end if;
 insert into plone27_justifications(grant_id,transaction_id,invoice_ref,amount) values(p_grant,p_tx,p_invoice,p_amount) returning plone27_justifications.id into jid; return jid; end $function$
$q$, $q$función plone27_justify(uuid,uuid,text,numeric,uuid)$q$, $q$drop function if exists plone27_justify(uuid,uuid,text,numeric,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_ledger_limits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a plone27_accounts; k text; j plone27_juniors; used numeric; dl numeric; jl numeric; begin
 if new.direction<>'debit' then return new; end if;
 select kind into k from plone27_transactions where id=new.transaction_id; if k in('reversal','tax_refund','membership') then return new; end if;
 select * into a from plone27_accounts where id=new.account_id;
 dl:=coalesce(a.daily_limit,nullif((plone27_setting('default_daily_limit',a.bank_id)#>>'{}')::numeric,0));
 if dl is not null then select coalesce(sum(e.amount),0) into used from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.account_id=new.account_id and e.direction='debit' and t.kind<>'reversal' and e.created_at::date=current_date;
  if used+new.amount>dl then raise exception 'Límite diario superado (% Pz)',dl; end if; end if;
 if a.kind='junior' then select * into j from plone27_juniors where account_id=a.id; jl:=coalesce(j.per_tx_limit,(plone27_setting('junior_default_limit',a.bank_id)#>>'{}')::numeric);
  if new.amount>jl then raise exception 'Junior: supera el límite por operación; requiere tutor'; end if; end if; return new; end $function$
$q$, $q$función plone27_ledger_limits()$q$, $q$drop function if exists plone27_ledger_limits()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_log_step(p_step text, p_err text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into plone27_incidents(kind,detail) values('finanzas_diario',jsonb_build_object('paso',p_step,'err',p_err)) $function$
$q$, $q$función plone27_log_step(text,text)$q$, $q$drop function if exists plone27_log_step(text,text)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_main_account(p_bank uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare acc uuid; begin
  select main_account into acc from plone27_banks where id=p_bank;
  if acc is null then raise exception 'La entidad no tiene cuenta principal configurada'; end if; return acc; end $function$
$q$, $q$función plone27_main_account(uuid)$q$, $q$drop function if exists plone27_main_account(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_mora_run(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
$q$, $q$función plone27_mora_run(uuid)$q$, $q$drop function if exists plone27_mora_run(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_next_id(p_kind text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare f plone27_numbering_formats; sc text; n bigint; id text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and status='published' and valid_from<=current_date order by version desc limit 1;
 if not found then raise exception 'Formato % sin publicar',p_kind; end if;
 sc:=case when f.year_scoped then extract(year from current_date)::text else 'global' end;
 n:=plone27_next_num(p_kind||':v'||f.version,sc,(power(10,f.width)-1)::bigint);
 id:=f.prefix||case when f.year_scoped then sc||'-' else '' end||lpad(n::text,f.width,'0');
 insert into plone27_issued_ids(identifier,kind) values(id,p_kind); return id; end $function$
$q$, $q$función plone27_next_id(text)$q$, $q$drop function if exists plone27_next_id(text)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_next_num(p_kind text, p_scope text, p_max bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare n bigint; begin
 insert into plone27_counters values(p_kind,p_scope,1) on conflict(kind,scope) do update set last=plone27_counters.last+1 returning last into n;
 if n>p_max then raise exception 'Capacidad agotada (% / %)',p_kind,p_scope; end if; return n; end $function$
$q$, $q$función plone27_next_num(text,text,bigint)$q$, $q$drop function if exists plone27_next_num(text,text,bigint)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_numbering_propose(p_kind text, p_prefix text, p_year boolean, p_width integer, p_reason text, p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare v int; begin
 select coalesce(max(version),0)+1 into v from plone27_numbering_formats where kind=p_kind;
 insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,reason,author) values(p_kind,v,p_prefix,p_year,p_width,p_reason,p_actor); return v; end $function$
$q$, $q$función plone27_numbering_propose(text,text,boolean,integer,text,uuid)$q$, $q$drop function if exists plone27_numbering_propose(text,text,boolean,integer,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_numbering_publish(p_kind text, p_version integer, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
 if plone27_numbering_simulate(p_kind,p_version,p_actor)->>'collides'='true' then raise exception 'Colisión de formato'; end if;
 update plone27_numbering_formats set status='published',approved_by=p_actor,valid_from=current_date where kind=p_kind and version=p_version and status='draft';
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'numbering_publish',p_kind,p_version::text); end $function$
$q$, $q$función plone27_numbering_publish(text,integer,uuid)$q$, $q$drop function if exists plone27_numbering_publish(text,integer,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_numbering_simulate(p_kind text, p_version integer, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare f plone27_numbering_formats; s text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and version=p_version;
 s:=f.prefix||case when f.year_scoped then extract(year from current_date)||'-' else '' end||lpad('1',f.width,'0');
 return jsonb_build_object('sample',s,'collides',exists(select 1 from plone27_issued_ids where identifier=s),'capacity',power(10,f.width)-1); end $function$
$q$, $q$función plone27_numbering_simulate(text,integer,uuid)$q$, $q$drop function if exists plone27_numbering_simulate(text,integer,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_on_reversed()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if new.status='reversed' and old.status<>'reversed' then
  if new.kind='reversal' then raise exception 'No se puede revertir una reversión'; end if;
  update plone27_tax_receipts r set paid_amount=greatest(r.paid_amount-d.s,0),paid_tx=null,status=case when r.paid_amount-d.s>0 then 'partial' else 'issued' end
   from (select coalesce(sum(amount),0) s from plone27_ledger_entries where transaction_id=new.id and direction='debit') d where r.paid_tx=new.id; end if; return new; end $function$
$q$, $q$función plone27_on_reversed()$q$, $q$drop function if exists plone27_on_reversed()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_open_account(p_bank uuid, p_kind text, p_name text, p_owner uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare vc text; i text; id uuid; begin
 select b.code into vc from plone27_banks b where b.id=p_bank and b.status='active'; if vc is null then raise exception 'Entidad inexistente o no activa'; end if;
 i:='PZ-'||vc||'-'||lpad(plone27_next_num('ACC',vc,9999)::text,4,'0');
 insert into plone27_accounts(bank_id,kind,name,owner_user,iban,allow_negative) values(p_bank,p_kind,p_name,p_owner,i,p_kind='system') returning plone27_accounts.id into id;
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'open_account','account',i); return jsonb_build_object('id',id,'iban',i); end $function$
$q$, $q$función plone27_open_account(uuid,text,text,uuid,uuid)$q$, $q$drop function if exists plone27_open_account(uuid,text,text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_open_account_p(p_product uuid, p_name text, p_owner uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p plone27_products; k text; r jsonb; begin
 select * into p from plone27_products where id=p_product and status='active' and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
 if p.id is null then raise exception 'Producto no disponible'; end if;
 if p.kind not like 'account\_%' and p.kind<>'internal_credit' then raise exception 'No es un producto de cuenta'; end if;
 k:=case p.kind when 'account_business' then 'business' when 'account_shared' then 'shared' when 'account_junior' then 'junior' else 'personal' end;
 r:=plone27_open_account(p.bank_id,k,p_name,p_owner,p_actor);
 update plone27_accounts set product_id=p_product,daily_limit=coalesce(p.daily_limit,daily_limit),allow_negative=(p.kind='internal_credit'),credit_limit=case when p.kind='internal_credit' then coalesce(p.credit_limit,0) else 0 end where id=(r->>'id')::uuid; return r; end $function$
$q$, $q$función plone27_open_account_p(uuid,text,uuid,uuid)$q$, $q$drop function if exists plone27_open_account_p(uuid,text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_open_bank(p_name text, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare c text; id uuid; begin
 c:=lpad(plone27_next_num('BANK','global',9999)::text,4,'0'); insert into plone27_banks(code,name) values(c,p_name) returning plone27_banks.id into id; return jsonb_build_object('id',id,'code',c); end $function$
$q$, $q$función plone27_open_bank(text,uuid)$q$, $q$drop function if exists plone27_open_bank(text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_payroll_run(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
$q$, $q$función plone27_payroll_run(uuid)$q$, $q$drop function if exists plone27_payroll_run(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_plan_create(p_key text, p_kind text, p_debtor uuid, p_beneficiary uuid, p_principal numeric, p_installments integer, p_start date, p_approved_by uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
$q$, $q$función plone27_plan_create(text,text,uuid,uuid,numeric,integer,date,uuid,uuid)$q$, $q$drop function if exists plone27_plan_create(text,text,uuid,uuid,numeric,integer,date,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_plan_schedule(p_principal numeric, p_rate numeric, p_n integer, p_start date, p_anchor integer)
 RETURNS TABLE(seq integer, due_date date, principal_part numeric, interest_part numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare m numeric:=p_rate/1200; cuota numeric; saldo numeric:=p_principal; i_p numeric; c_p numeric; k int; begin
  if p_n<1 then raise exception 'Número de cuotas inválido'; end if;
  cuota:=case when m=0 then round(p_principal/p_n,2) else round(p_principal*m/(1-power(1+m,-p_n)),2) end;
  for k in 1..p_n loop
    i_p:=round(saldo*m,2);
    c_p:=case when k=p_n then saldo else cuota-i_p end;
    saldo:=saldo-c_p;
    seq:=k; due_date:=plone27_add_months(p_start,k,p_anchor); principal_part:=c_p; interest_part:=i_p;
    return next;
  end loop; end $function$
$q$, $q$función plone27_plan_schedule(numeric,numeric,integer,date,integer)$q$, $q$drop function if exists plone27_plan_schedule(numeric,numeric,integer,date,integer)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_plans_collect(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
$q$, $q$función plone27_plans_collect(uuid)$q$, $q$drop function if exists plone27_plans_collect(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_policy_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ declare p jsonb:=new.params; begin
 if tg_op='UPDATE' and old.status='published' and (new.params is distinct from old.params or new.scope is distinct from old.scope or new.bank_id is distinct from old.bank_id or new.customer_id is distinct from old.customer_id or new.dip is distinct from old.dip or new.kind is distinct from old.kind)
  then raise exception 'Norma publicada inmutable: crea una nueva'; end if;
 if (new.scope='bank' and new.bank_id is null) or (new.scope='customer' and new.customer_id is null) or (new.scope='dip' and new.dip is null) then raise exception 'La norma no indica su destinatario'; end if;
 if new.kind='penalty' then
  if coalesce(p->>'type','') not in('percent','fixed') or p->>'value' is null or (p->>'value')::numeric<0 then raise exception 'Recargo: indica type (percent|fixed) y value'; end if;
  if p->>'type'='percent' and (p->>'value')::numeric>(plone27_setting('penalty_max_pct')#>>'{}')::numeric then raise exception 'Supera el tope central de recargo'; end if;
 elsif new.kind='dispute' then
  if coalesce((p->>'max_days')::int,0)<1 or (p->>'max_days')::int>(plone27_setting('dispute_max_days')#>>'{}')::numeric then raise exception 'Disputa: max_days fuera del tope central'; end if;
 elsif coalesce((p->>'interest_pct')::numeric,0)>(plone27_setting('debt_max_interest_pct')#>>'{}')::numeric then raise exception 'Supera el tope central de interés'; end if;
 if new.status='published' and new.approved_by is null then raise exception 'Publicar exige aprobación registrada'; end if; return new; end $function$
$q$, $q$función plone27_policy_guard()$q$, $q$drop function if exists plone27_policy_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_policy_resolve(p_kind text, p_account uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a plone27_accounts; v_dip text; ids uuid[]; r jsonb; begin
 select * into a from plone27_accounts where id=p_account; select c.dip into v_dip from plone27_customers c where c.id=a.customer_id;
 with c as(select p.id,case p.scope when 'global' then 1 when 'bank' then 2 else 3 end lvl from plone27_policies p where p.kind=p_kind and p.status='published' and current_date>=p.valid_from and (p.valid_to is null or current_date<=p.valid_to)
  and (p.scope='global' or (p.scope='bank' and p.bank_id=a.bank_id) or (p.scope='customer' and p.customer_id=a.customer_id) or (p.scope='dip' and p.dip=v_dip)))
 select array_agg(c.id) into ids from c where c.lvl=(select max(lvl) from c);
 if ids is null then return null; end if;
 if array_length(ids,1)>1 then insert into plone27_incidents(kind,detail) values('policy_conflict',jsonb_build_object('kind',p_kind,'account',p_account,'policies',ids)); return null; end if;
 select p.params||jsonb_build_object('policy',p.id,'approved_by',p.approved_by) into r from plone27_policies p where p.id=ids[1]; return r; end $function$
$q$, $q$función plone27_policy_resolve(text,uuid)$q$, $q$drop function if exists plone27_policy_resolve(text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_post(p_key text, p_kind text, p_memo text, p_lines jsonb, p_actor uuid, p_reverses uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'post',p_kind,tx::text,p_lines); return tx; end $function$
$q$, $q$función plone27_post(text,text,text,jsonb,uuid,uuid)$q$, $q$drop function if exists plone27_post(text,text,text,jsonb,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_product_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if new.status is distinct from old.status then
  if (old.status,new.status) not in(('draft','active'),('active','retired'),('draft','retired')) then raise exception 'Transición de producto % → % no permitida',old.status,new.status; end if;
  if new.status='active' and new.approved_by is null then raise exception 'Activar un producto requiere aprobación registrada'; end if; end if; return new; end $function$
$q$, $q$función plone27_product_guard()$q$, $q$drop function if exists plone27_product_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_rate_hit(p_client uuid)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 insert into plone27_api_usage values(p_client,date_trunc('minute',now()),1) on conflict(client_id,minute) do update set hits=plone27_api_usage.hits+1 returning hits $function$
$q$, $q$función plone27_rate_hit(uuid)$q$, $q$drop function if exists plone27_rate_hit(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_rbu_claim(p_bonus uuid, p_user uuid, p_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b plone27_rbu_bonuses; tx uuid; src uuid; begin
  select * into b from plone27_rbu_bonuses where id=p_bonus for update;
  if b.id is null or b.owner_user is distinct from p_user then raise exception 'Bono no encontrado'; end if;
  if b.status='claimed' then return b.claimed_tx; end if;
  if b.status<>'available' or b.expires_on<=current_date then raise exception 'Bono caducado'; end if;
  src:=plone27_rbu_source();
  if plone27_available(src)<b.amount then raise exception 'Cuenta de origen de la RBU sin fondos suficientes'; end if;
  tx:=plone27_transfer(p_key,src,b.wallet_account,b.amount,'RBU semanal',p_user);
  update plone27_rbu_bonuses set status='claimed',claimed_at=now(),claimed_tx=tx where id=p_bonus;
  return tx; end $function$
$q$, $q$función plone27_rbu_claim(uuid,uuid,text)$q$, $q$drop function if exists plone27_rbu_claim(uuid,uuid,text)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_rbu_expire(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n int; begin
  with x as(update plone27_rbu_bonuses set status='expired' where status='available' and expires_on<=current_date returning 1)
  select count(*) into n from x; return n; end $function$
$q$, $q$función plone27_rbu_expire(uuid)$q$, $q$drop function if exists plone27_rbu_expire(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_rbu_issue_week(p_week date, p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  end loop; return n; end $function$
$q$, $q$función plone27_rbu_issue_week(date,uuid)$q$, $q$drop function if exists plone27_rbu_issue_week(date,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_rbu_source()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare acc uuid; begin
  select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_rbu_origen';
  if acc is null then acc:=plone27_reserve_account(); end if;
  return acc; end $function$
$q$, $q$función plone27_rbu_source()$q$, $q$drop function if exists plone27_rbu_source()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_receipt_certificate(p_receipt uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('recibo',r.ref,'norma',ru.code,'version',v.version,'huella_norma',c.fingerprint,'base',c.base,'importe',c.amount,
    'calculo',c.inputs,'tipo',c.kind,'seq',c.seq,'hash',c.hash,'hash_anterior',c.prev_hash,'reemplaza',c.reemplaza,
    'emitido',c.created_at,'certificados_del_recibo',(select count(*) from plone27_tax_certificates h where h.subject_id=p_receipt))
  from (select * from plone27_tax_certificates where subject_id=p_receipt order by seq desc limit 1) c
    join plone27_tax_receipts r on r.id=c.subject_id
    join plone27_tax_rule_versions v on v.id=c.version_id join plone27_tax_rules ru on ru.id=v.rule_id $function$
$q$, $q$función plone27_receipt_certificate(uuid)$q$, $q$drop function if exists plone27_receipt_certificate(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_receipt_paid()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if new.status='paid' and new.paid_amount<new.amount then new.paid_amount:=new.amount; end if; return new; end $function$
$q$, $q$función plone27_receipt_paid()$q$, $q$drop function if exists plone27_receipt_paid()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_receipt_routing()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
  new.obligor_account:=nullif(current_setting('plone27.obligor',true),'')::uuid;
  new.operation_ref:=nullif(current_setting('plone27.operacion',true),'');
  return new; end $function$
$q$, $q$función plone27_receipt_routing()$q$, $q$drop function if exists plone27_receipt_routing()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_ref_lock()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if new.ref is distinct from old.ref then raise exception 'Referencia inmutable'; end if; return new; end $function$
$q$, $q$función plone27_ref_lock()$q$, $q$drop function if exists plone27_ref_lock()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_reimb_ref()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
 if new.status='paid' and new.reimb_ref is null then new.reimb_ref:=plone27_next_id('REE'); end if; return new; end $function$
$q$, $q$función plone27_reimb_ref()$q$, $q$drop function if exists plone27_reimb_ref()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_reimburse(p_key text, p_just uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j plone27_justifications; g plone27_grants; f uuid; tx uuid; begin
 select * into j from plone27_justifications where id=p_just for update; if j.status not in('pending','approved') then raise exception 'Ya pagada o rechazada'; end if;
 select * into g from plone27_grants where id=j.grant_id for update; select funding_account into f from plone27_grant_programs where id=g.program_id;
 if j.status='pending' then update plone27_grants set approved=approved+j.amount where id=g.id; update plone27_justifications set status='approved' where id=p_just; end if;
 if plone27_available(f)<j.amount then return null; end if;   -- sin fondos: queda aprobado/pendiente, nunca "pagado"
 tx:=plone27_transfer(p_key,f,g.beneficiary_account,j.amount,'Reembolso',p_actor);
 update plone27_grants set paid=paid+j.amount where id=g.id; update plone27_justifications set status='paid' where id=p_just; return tx; end $function$
$q$, $q$función plone27_reimburse(text,uuid,uuid)$q$, $q$drop function if exists plone27_reimburse(text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_release(p_res uuid, p_actor uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ update plone27_reservations set status='released' where id=p_res and status='active' $function$
$q$, $q$función plone27_release(uuid,uuid)$q$, $q$drop function if exists plone27_release(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_reserve(p_account uuid, p_amount numeric, p_reason text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare rid uuid; begin
 perform 1 from plone27_accounts where id=p_account for update;
 if p_amount<=0 or plone27_available(p_account)<p_amount then raise exception 'Saldo disponible insuficiente'; end if;
 insert into plone27_reservations(account_id,amount,reason) values(p_account,p_amount,p_reason) returning plone27_reservations.id into rid; return rid; end $function$
$q$, $q$función plone27_reserve(uuid,numeric,text,uuid)$q$, $q$drop function if exists plone27_reserve(uuid,numeric,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_reserve_account()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare acc uuid; begin
  select nullif(value,'')::uuid into acc from plone27_config where key='cuenta_reserva';
  if acc is null then raise exception 'Falta la Cuenta de Reserva del Grupo (ejecuta el seed 0011)'; end if; return acc; end $function$
$q$, $q$función plone27_reserve_account()$q$, $q$drop function if exists plone27_reserve_account()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_reverse(p_key text, p_tx uuid, p_reason text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare r uuid; lines jsonb; begin
  if exists(select 1 from plone27_transactions where id=p_tx and status='reversed') then raise exception 'Ya revertida'; end if;
  select jsonb_agg(jsonb_build_object('account',account_id,'dir',case direction when 'debit' then 'credit' else 'debit' end,'amount',amount))
    into lines from plone27_ledger_entries where transaction_id=p_tx;
  r:=plone27_post(p_key,'reversal',p_reason,lines,p_actor,p_tx);
  update plone27_transactions set status='reversed' where id=p_tx;
  return r; end $function$
$q$, $q$función plone27_reverse(text,uuid,text,uuid)$q$, $q$drop function if exists plone27_reverse(text,uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_run_batch(p_batch uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare b plone27_batches; i record; ok int:=0; ko int:=0; begin
 select * into b from plone27_batches where id=p_batch for update;
 for i in select * from plone27_batch_items where batch_id=p_batch and status in('pending','failed') order by id loop
  begin perform plone27_transfer_fee('batch:'||i.id,b.from_account,i.to_account,i.amount,b.kind,p_actor); update plone27_batch_items set status='paid',error=null where id=i.id; ok:=ok+1;
  exception when others then update plone27_batch_items set status='failed',error=sqlerrm where id=i.id; ko:=ko+1; end; end loop;
 update plone27_batches set status=case when ko=0 then 'done' else 'partial' end where id=p_batch; return jsonb_build_object('paid',ok,'failed',ko); end $function$
$q$, $q$función plone27_run_batch(uuid,uuid)$q$, $q$drop function if exists plone27_run_batch(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_run_scheduled(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare s record; n int:=0; begin
 for s in select * from plone27_scheduled where status='active' and run_at<=now() order by run_at for update skip locked loop
  begin perform plone27_transfer_fee('sch:'||s.id||':'||s.run_at,s.from_account,s.to_account,s.amount,s.memo,p_actor); n:=n+1;
   if s.recurrence is null then update plone27_scheduled set status='done' where id=s.id; else update plone27_scheduled set run_at=run_at+recurrence where id=s.id; end if;
  exception when others then insert into plone27_incidents(kind,detail) values('scheduled_failed',jsonb_build_object('id',s.id,'err',sqlerrm)); end;
 end loop; return n; end $function$
$q$, $q$función plone27_run_scheduled(uuid)$q$, $q$drop function if exists plone27_run_scheduled(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_rv_cap()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ declare m numeric; begin
 select max_rate into m from plone27_tax_rules where id=new.rule_id;
 if (new.scope_bank is not null or new.scope_op is not null) and m is not null and new.method='percent' and new.rate>m then raise exception 'Regla específica supera el límite central (%)',m; end if; return new; end $function$
$q$, $q$función plone27_rv_cap()$q$, $q$drop function if exists plone27_rv_cap()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_rv_guard()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
  if old.status='published' then raise exception 'Versión publicada inmutable; crea una nueva'; end if;
  if new.status='published' and (new.approver is null or new.approver is not distinct from new.author and false) then raise exception 'Requiere aprobador'; end if;
  return new; end $function$
$q$, $q$función plone27_rv_guard()$q$, $q$drop function if exists plone27_rv_guard()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_sale(p_key text, p_buyer uuid, p_seller uuid, p_base numeric, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  return tx; end $function$
$q$, $q$función plone27_sale(text,uuid,uuid,numeric,uuid)$q$, $q$drop function if exists plone27_sale(text,uuid,uuid,numeric,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_security_report()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select coalesce(jsonb_agg(jsonb_build_object('check',c,'severity',sv,'count',n,'detail',dt)),'[]'::jsonb) from (
  select 'Tablas sin RLS' c,'critical' sv,count(*) n,'Tablas plone27_* con seguridad por filas desactivada' dt from pg_class c join pg_namespace s on s.oid=c.relnamespace where s.nspname='public' and c.relkind='r' and c.relname like 'plone27\_%' and not c.relrowsecurity
  union all select 'Políticas que permiten escribir','critical',count(*),'Las escrituras solo deben pasar por el servidor' from pg_policies where schemaname='public' and tablename like 'plone27\_%' and cmd<>'SELECT'
  union all select 'Funciones ejecutables por anon/authenticated','critical',count(*),'Solo service_role debe ejecutarlas' from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute'))
  union all select 'Webhooks sin https','critical',count(*),'' from plone27_webhooks where url !~ '^https://'
  union all select 'Claves de API sin permisos','warning',count(*),'' from plone27_api_clients where active and cardinality(scopes)=0
  union all select 'Sin administradores activos','critical',case when count(*)=0 then 1 else 0 end,'' from plone27_staff where role='admin' and active
  union all select 'Más de 3 administradores activos','warning',case when count(*)>3 then count(*) else 0 end,'Principio de mínimo privilegio' from plone27_staff where role='admin' and active
  union all select 'Cambios sensibles pendientes de aprobar','info',count(*),'' from plone27_setting_changes where status='pending') q $function$
$q$, $q$función plone27_security_report()$q$, $q$drop function if exists plone27_security_report()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_set_junior_payer(p_bank uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  if not exists(select 1 from plone27_banks where id=p_bank and main_account is not null) then raise exception 'La entidad necesita cuenta principal'; end if;
  insert into plone27_config(key,value) values('entidad_capitalia',p_bank::text) on conflict(key) do update set value=excluded.value;
  insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'junior_payer','bank',p_bank::text);
end $function$
$q$, $q$función plone27_set_junior_payer(uuid,uuid)$q$, $q$drop function if exists plone27_set_junior_payer(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_set_ref()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare k text:=tg_argv[0]; begin
 if tg_table_name='plone27_grants' then select case p.kind when 'bono' then 'BON' else 'SUB' end into k from plone27_grant_programs p where p.id=new.program_id; end if;
 if new.ref is null then new.ref:=plone27_next_id(k); end if; return new; end $function$
$q$, $q$función plone27_set_ref()$q$, $q$drop function if exists plone27_set_ref()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_setting(p_key text, p_bank uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare v jsonb; begin
 select coalesce((select b.value from plone27_bank_settings b where b.bank_id=p_bank and b.key=p_key),s.value) into v from plone27_settings s where s.key=p_key;
 if v is null then raise exception 'Ajuste desconocido: %',p_key; end if; return v; end $function$
$q$, $q$función plone27_setting(text,uuid)$q$, $q$drop function if exists plone27_setting(text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_setting_apply(p_change uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare c plone27_setting_changes; begin
 select * into c from plone27_setting_changes where id=p_change and status='pending' for update; if c.id is null then return; end if;
 if c.bank_id is null then update plone27_settings set value=c.new_value,version=version+1,updated_at=now() where key=c.key;
 else insert into plone27_bank_settings values(c.bank_id,c.key,c.new_value) on conflict(bank_id,key) do update set value=c.new_value; end if;
 update plone27_setting_changes set status='applied',approved_by=coalesce(approved_by,p_actor) where id=p_change;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'setting_applied','setting',c.key,jsonb_build_object('bank',c.bank_id,'new',c.new_value)); end $function$
$q$, $q$función plone27_setting_apply(uuid,uuid)$q$, $q$drop function if exists plone27_setting_apply(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_setting_approve(p_change uuid, p_approve boolean, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare c plone27_setting_changes; begin
 select * into c from plone27_setting_changes where id=p_change and status='pending'; if c.id is null then raise exception 'Cambio no pendiente'; end if;
 if c.proposed_by is not distinct from p_actor then raise exception 'El proponente no puede aprobar su propio cambio'; end if;
 if p_approve then update plone27_setting_changes set approved_by=p_actor where id=p_change; perform plone27_setting_apply(p_change,p_actor);
 else update plone27_setting_changes set status='rejected',approved_by=p_actor where id=p_change; end if; end $function$
$q$, $q$función plone27_setting_approve(uuid,boolean,uuid)$q$, $q$drop function if exists plone27_setting_approve(uuid,boolean,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_setting_propose(p_key text, p_value jsonb, p_bank uuid, p_reason text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s plone27_settings; id uuid; begin
 select * into s from plone27_settings where key=p_key; perform plone27_setting_validate(p_key,p_value);
 if p_bank is not null and not s.bank_overridable then raise exception 'Este ajuste solo es central'; end if; if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 insert into plone27_setting_changes(key,bank_id,new_value,old_value,reason,proposed_by) values(p_key,p_bank,p_value,plone27_setting(p_key,p_bank),p_reason,p_actor) returning plone27_setting_changes.id into id;
 if not s.sensitive then perform plone27_setting_apply(id,p_actor); end if; return id; end $function$
$q$, $q$función plone27_setting_propose(text,jsonb,uuid,text,uuid)$q$, $q$drop function if exists plone27_setting_propose(text,jsonb,uuid,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_setting_validate(p_key text, p_value jsonb)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
AS $function$ declare s plone27_settings; begin
 select * into s from plone27_settings where key=p_key; if s.key is null then raise exception 'Ajuste desconocido'; end if;
 if s.vtype='number' then if jsonb_typeof(p_value)<>'number' or (p_value#>>'{}')::numeric<coalesce(s.min_v,-1e18) or (p_value#>>'{}')::numeric>coalesce(s.max_v,1e18) then raise exception 'Fuera de los límites centrales [% , %]',s.min_v,s.max_v; end if;
 elsif s.vtype='boolean' then if jsonb_typeof(p_value)<>'boolean' then raise exception 'Se esperaba booleano'; end if;
 elsif s.vtype='enum' then if not (p_value#>>'{}')=any(s.allowed) then raise exception 'Valor no permitido (%)',s.allowed; end if;
 elsif jsonb_typeof(p_value)<>'string' then raise exception 'Se esperaba texto'; end if; end $function$
$q$, $q$función plone27_setting_validate(text,jsonb)$q$, $q$drop function if exists plone27_setting_validate(text,jsonb)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_settle_bank(p_bank uuid, p_from date, p_to date, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ declare sid uuid; begin
 select id into sid from plone27_settlements where bank_id=p_bank and period_from=p_from and period_to=p_to; if sid is not null then return sid; end if;
 insert into plone27_settlements(bank_id,period_from,period_to,evaluated,collected,pending,refunded)
  select p_bank,p_from,p_to,coalesce(sum(r.amount),0),coalesce(sum(r.amount) filter(where r.status='paid'),0),coalesce(sum(r.amount) filter(where r.status='issued'),0),coalesce(sum(r.refunded),0)
  from plone27_tax_receipts r join plone27_accounts a on a.id=r.account_id where a.bank_id=p_bank and r.created_at::date between p_from and p_to returning plone27_settlements.id into sid; return sid; end $function$
$q$, $q$función plone27_settle_bank(uuid,date,date,uuid)$q$, $q$drop function if exists plone27_settle_bank(uuid,date,date,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_staff_set(p_user uuid, p_role text, p_active boolean, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
 insert into plone27_staff(user_id,role,active) values(p_user,p_role,p_active) on conflict(user_id) do update set role=p_role,active=p_active;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'staff_set','staff',p_user::text,jsonb_build_object('role',p_role,'active',p_active)); end $function$
$q$, $q$función plone27_staff_set(uuid,text,boolean,uuid)$q$, $q$drop function if exists plone27_staff_set(uuid,text,boolean,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_sub_create()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin
 if new.kind='junior' and new.product_id is not null and old.product_id is null then insert into plone27_subscriptions(account_id,product_id) values(new.id,new.product_id) on conflict do nothing; end if; return new; end $function$
$q$, $q$función plone27_sub_create()$q$, $q$drop function if exists plone27_sub_create()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_subscription_renew(p_account uuid, p_user uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 return jsonb_build_object('renewed',true,'period_end',ne,'transaction',tx); end $function$
$q$, $q$función plone27_subscription_renew(uuid,uuid,uuid)$q$, $q$drop function if exists plone27_subscription_renew(uuid,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_subscriptions_sweep(p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s record; r jsonb; ren int:=0; exp int:=0; g int:=(plone27_setting('junior_membership_grace_days')#>>'{}')::int; begin
 for s in select * from plone27_subscriptions where status in('active','past_due') and period_end<=current_date loop
  if s.auto_renew then r:=plone27_subscription_renew(s.account_id,null,p_actor); if (r->>'renewed')='true' then ren:=ren+1; continue; end if; end if;
  if s.period_end+g<current_date then update plone27_subscriptions set status='expired' where id=s.id; exp:=exp+1; else update plone27_subscriptions set status='past_due' where id=s.id and status='active'; end if; end loop;
 return jsonb_build_object('renewed',ren,'expired',exp); end $function$
$q$, $q$función plone27_subscriptions_sweep(uuid)$q$, $q$drop function if exists plone27_subscriptions_sweep(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_t57_run(p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  end loop; return n; end $function$
$q$, $q$función plone27_t57_run(uuid)$q$, $q$drop function if exists plone27_t57_run(uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_calc(p_version uuid, p_base numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
 select round(least(coalesce(v.max_amount,'infinity'),greatest(coalesce(v.min_amount,0),
   case v.method
    when 'percent' then p_base*v.rate/100
    when 'fixed' then v.rate
    when 'brackets' then coalesce((select sum((least(p_base,coalesce(b.to_amount,'infinity'))-b.from_amount)*b.rate/100)
                                    from plone27_tax_brackets b where b.version_id=v.id and p_base>b.from_amount),0)
    else coalesce((select p_base*b.rate/100 from plone27_tax_brackets b where b.version_id=v.id and p_base>b.from_amount
                   and (b.to_amount is null or p_base<=b.to_amount) limit 1),0)
   end)),2)
 from plone27_tax_rule_versions v where v.id=p_version $function$
$q$, $q$función plone27_tax_calc(uuid,numeric)$q$, $q$drop function if exists plone27_tax_calc(uuid,numeric)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_declare(p_code text, p_account uuid, p_periodo text, p_base numeric, p_declarante uuid, p_aprobador uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare rid uuid; due date:=current_date+(plone27_setting('default_receipt_due_days')#>>'{}')::int; begin
  if p_aprobador is null or p_aprobador is not distinct from p_declarante then raise exception 'La declaración exige la aprobación de otra persona'; end if;
  if (select kind from plone27_accounts where id=p_account)='junior' then
    rid:=plone27_tax_issue_junior(p_code,p_account,p_base,'decl:'||p_code||':'||p_account||':'||p_periodo,null,'declaracion',due,p_actor);
  else
    perform set_config('plone27.operacion','declaracion:'||p_periodo||':aprobada_por:'||p_aprobador::text,true);
    rid:=plone27_tax_issue(p_code,p_account,p_base,'decl:'||p_code||':'||p_account||':'||p_periodo,null,'declaracion',due,p_actor);
    perform set_config('plone27.operacion','',true);
  end if;
  return rid; end $function$
$q$, $q$función plone27_tax_declare(text,uuid,text,numeric,uuid,uuid,uuid)$q$, $q$drop function if exists plone27_tax_declare(text,uuid,text,numeric,uuid,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_issue(p_code text, p_account uuid, p_base numeric, p_event_key text, p_op text, p_pathway text, p_due date, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 insert into plone27_tax_receipts(rule_version_id,account_id,base,amount,due_date,evaluation_id) values(v,p_account,p_base,amt,p_due,ev) returning id into rid; return rid; end $function$
$q$, $q$función plone27_tax_issue(text,uuid,numeric,text,text,text,date,uuid)$q$, $q$drop function if exists plone27_tax_issue(text,uuid,numeric,text,text,text,date,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_issue_bank(p_code text, p_bank uuid, p_base numeric, p_event_key text, p_op text, p_pathway text, p_due date, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare acc uuid; begin
  select coalesce(tax_account,main_account) into acc from plone27_banks where id=p_bank;
  if acc is null then raise exception 'La entidad no tiene cuenta de impuestos ni principal'; end if;
  return plone27_tax_issue(p_code,acc,p_base,p_event_key,p_op,p_pathway,p_due,p_actor); end $function$
$q$, $q$función plone27_tax_issue_bank(text,uuid,numeric,text,text,text,date,uuid)$q$, $q$drop function if exists plone27_tax_issue_bank(text,uuid,numeric,text,text,text,date,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_issue_junior(p_code text, p_junior uuid, p_base numeric, p_event_key text, p_op text, p_pathway text, p_due date, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare payer uuid; rid uuid; begin
  if (select kind from plone27_accounts where id=p_junior) is distinct from 'junior' then raise exception 'La cuenta no es Junior'; end if;
  payer:=plone27_junior_tax_payer();
  perform set_config('plone27.obligor',p_junior::text,true);
  perform set_config('plone27.operacion',p_event_key,true);
  rid:=plone27_tax_issue(p_code,payer,p_base,p_event_key,p_op,p_pathway,p_due,p_actor);
  perform set_config('plone27.obligor','',true); perform set_config('plone27.operacion','',true);
  return rid; end $function$
$q$, $q$función plone27_tax_issue_junior(text,uuid,numeric,text,text,text,date,uuid)$q$, $q$drop function if exists plone27_tax_issue_junior(text,uuid,numeric,text,text,text,date,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_pay(p_key text, p_receipt uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; dl jsonb; ds numeric; lines jsonb; tx uuid; begin
 select t.*,ru.collector_account col,ru.id rule into r from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id where t.id=p_receipt for update of t;
 if r.status='paid' then return r.paid_tx; end if; if r.status<>'issued' then raise exception 'Recibo no cobrable'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('account',account_id,'dir','credit','amount',round(r.amount*pct/100,2))),'[]'),coalesce(sum(round(r.amount*pct/100,2)),0) into dl,ds from plone27_tax_distribution where rule_id=r.rule;
 lines:=jsonb_build_array(jsonb_build_object('account',r.account_id,'dir','debit','amount',r.amount))||dl;
 if r.amount-ds>0 then lines:=lines||jsonb_build_object('account',r.col,'dir','credit','amount',r.amount-ds); end if;
 tx:=plone27_post(p_key,'tax_payment',null,lines,p_actor);
 update plone27_tax_receipts set status='paid',paid_tx=tx where id=p_receipt; return tx; end $function$
$q$, $q$función plone27_tax_pay(text,uuid,uuid)$q$, $q$drop function if exists plone27_tax_pay(text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_pay_partial(p_key text, p_receipt uuid, p_amount numeric, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; dl jsonb; ds numeric; lines jsonb; tx uuid; done boolean; begin
 select t.*,ru.collector_account col,ru.id rule into r from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id where t.id=p_receipt for update of t;
 if r.status not in('issued','partial') then raise exception 'Recibo no cobrable'; end if;
 if p_amount<=0 or r.paid_amount+p_amount>r.amount then raise exception 'Importe de pago inválido'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('account',account_id,'dir','credit','amount',round(p_amount*pct/100,2))),'[]'),coalesce(sum(round(p_amount*pct/100,2)),0) into dl,ds from plone27_tax_distribution where rule_id=r.rule;
 lines:=jsonb_build_array(jsonb_build_object('account',r.account_id,'dir','debit','amount',p_amount))||dl;
 if p_amount-ds>0 then lines:=lines||jsonb_build_object('account',r.col,'dir','credit','amount',p_amount-ds); end if;
 tx:=plone27_post(p_key,'tax_payment',null,lines,p_actor); done:=r.paid_amount+p_amount=r.amount;
 update plone27_tax_receipts set paid_amount=paid_amount+p_amount,status=case when done then 'paid' else 'partial' end,paid_tx=case when done then tx else paid_tx end where id=p_receipt; return tx; end $function$
$q$, $q$función plone27_tax_pay_partial(text,uuid,numeric,uuid)$q$, $q$drop function if exists plone27_tax_pay_partial(text,uuid,numeric,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_publish(p_version uuid, p_approver uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v plone27_tax_rule_versions; begin
  select * into v from plone27_tax_rule_versions where id=p_version for update;
  if v.id is null or v.status<>'draft' then raise exception 'La versión no está en borrador'; end if;
  if p_approver is null or p_approver is not distinct from v.author then raise exception 'Publicar exige un aprobador distinto del autor'; end if;
  update plone27_tax_rule_versions set status='published',approver=p_approver,published_at=now(),fingerprint=plone27_version_fp(p_version) where id=p_version;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_publish','tax_version',p_version::text,jsonb_build_object('approver',p_approver));
end $function$
$q$, $q$función plone27_tax_publish(uuid,uuid,uuid)$q$, $q$drop function if exists plone27_tax_publish(uuid,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_set_destination(p_code text, p_account uuid, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare old uuid; begin
  if not plone27_es_institucional(p_account) then raise exception 'El destino debe ser una cuenta institucional'; end if;
  select collector_account into old from plone27_tax_rules where code=p_code;
  if not found then raise exception 'Impuesto desconocido: %',p_code; end if;
  update plone27_tax_rules set collector_account=p_account where code=p_code;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_destination','tax_rule',p_code,jsonb_build_object('anterior',old,'nuevo',p_account));
end $function$
$q$, $q$función plone27_tax_set_destination(text,uuid,uuid)$q$, $q$drop function if exists plone27_tax_set_destination(text,uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tax_trace(p_version uuid, p_base numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
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
  return res; end $function$
$q$, $q$función plone27_tax_trace(uuid,numeric)$q$, $q$drop function if exists plone27_tax_trace(uuid,numeric)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_transfer(p_key text, p_from uuid, p_to uuid, p_amount numeric, p_memo text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
  if p_from=p_to or p_amount<=0 then raise exception 'Transferencia inválida'; end if;
  return plone27_post(p_key,'transfer',p_memo,jsonb_build_array(
    jsonb_build_object('account',p_from,'dir','debit','amount',p_amount),
    jsonb_build_object('account',p_to,'dir','credit','amount',p_amount)),p_actor);
end $function$
$q$, $q$función plone27_transfer(text,uuid,uuid,numeric,text,uuid)$q$, $q$drop function if exists plone27_transfer(text,uuid,uuid,numeric,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_transfer_fee(p_key text, p_from uuid, p_to uuid, p_amount numeric, p_memo text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 return plone27_post(p_key,'transfer',p_memo,lines,p_actor); end $function$
$q$, $q$función plone27_transfer_fee(text,uuid,uuid,numeric,text,uuid)$q$, $q$drop function if exists plone27_transfer_fee(text,uuid,uuid,numeric,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_transfer_user(p_key text, p_user uuid, p_from uuid, p_to uuid, p_amount numeric, p_memo text, p_actor uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
 if not exists(select 1 from plone27_account_members where account_id=p_from and user_id=p_user) and not exists(select 1 from plone27_juniors where account_id=p_from and guardian_user=p_user)
  then raise exception 'El usuario no está autorizado en la cuenta de origen'; end if;
 return plone27_transfer_fee(p_key,p_from,p_to,p_amount,p_memo,p_actor); end $function$
$q$, $q$función plone27_transfer_user(text,uuid,uuid,uuid,numeric,text,uuid)$q$, $q$drop function if exists plone27_transfer_user(text,uuid,uuid,uuid,numeric,text,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_tx_refs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ begin
 new.ref:=plone27_next_id('OPE'); if new.kind='transfer' then new.transfer_ref:=plone27_next_id('TRF'); end if; return new; end $function$
$q$, $q$función plone27_tx_refs()$q$, $q$drop function if exists plone27_tx_refs()$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_user_can(p_user uuid, p_account uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from plone27_account_members where account_id=p_account and user_id=p_user) or exists(select 1 from plone27_juniors where account_id=p_account and guardian_user=p_user)
  or exists(select 1 from plone27_accounts a join plone27_junior_profiles j on j.customer_id=a.customer_id where a.id=p_account and j.guardian_user=p_user) $function$
$q$, $q$función plone27_user_can(uuid,uuid)$q$, $q$drop function if exists plone27_user_can(uuid,uuid)$q$);
select pg_temp.ddl($q$CREATE OR REPLACE FUNCTION public.plone27_version_fp(p_version uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select encode(sha256(convert_to(coalesce((
    select jsonb_build_object('metodo',v.method,'tasa',v.rate::text,'minimo',v.min_amount::text,'maximo',v.max_amount::text,
      'desde',v.valid_from::text,'hasta',v.valid_to::text,'banco',v.scope_bank,'op',v.scope_op,
      'tramos',(select coalesce(jsonb_agg(jsonb_build_object('d',b.from_amount::text,'h',b.to_amount::text,'t',b.rate::text) order by b.from_amount),'[]'::jsonb)
                from plone27_tax_brackets b where b.version_id=v.id))::text
    from plone27_tax_rule_versions v where v.id=p_version),''),'utf8')),'hex') $function$
$q$, $q$función plone27_version_fp(uuid)$q$, $q$drop function if exists plone27_version_fp(uuid)$q$);
-- ===== 4. VALORES POR DEFECTO que usan funciones =====
-- ===== 5. CLAVES, ÚNICOS, CHECKS y FOREIGN KEYS =====
select pg_temp.k($q$plone27_account_members$q$,$q$plone27_account_members_pkey$q$,'p',$q$PRIMARY KEY (account_id, user_id)$q$);
select pg_temp.k($q$plone27_accounts$q$,$q$plone27_accounts_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_activities$q$,$q$plone27_activities_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_api_clients$q$,$q$plone27_api_clients_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_api_usage$q$,$q$plone27_api_usage_pkey$q$,'p',$q$PRIMARY KEY (client_id, minute)$q$);
select pg_temp.k($q$plone27_approvals$q$,$q$plone27_approvals_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_audit_log$q$,$q$plone27_audit_log_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_bank_settings$q$,$q$plone27_bank_settings_pkey$q$,'p',$q$PRIMARY KEY (bank_id, key)$q$);
select pg_temp.k($q$plone27_banks$q$,$q$plone27_banks_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_batch_items$q$,$q$plone27_batch_items_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_batches$q$,$q$plone27_batches_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_budgets$q$,$q$plone27_budgets_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_card_charges$q$,$q$plone27_card_charges_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_card_designs$q$,$q$plone27_card_designs_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_card_orders$q$,$q$plone27_card_orders_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_cards$q$,$q$plone27_cards_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_config$q$,$q$plone27_config_pkey$q$,'p',$q$PRIMARY KEY (key)$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_counters$q$,$q$plone27_counters_pkey$q$,'p',$q$PRIMARY KEY (kind, scope)$q$);
select pg_temp.k($q$plone27_customers$q$,$q$plone27_customers_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_debts$q$,$q$plone27_debts_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_design_purchases$q$,$q$plone27_design_purchases_pkey$q$,'p',$q$PRIMARY KEY (design_id, account_id)$q$);
select pg_temp.k($q$plone27_disputes$q$,$q$plone27_disputes_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_fee_rules$q$,$q$plone27_fee_rules_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_grant_programs$q$,$q$plone27_grant_programs_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_grants$q$,$q$plone27_grants_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_incidents$q$,$q$plone27_incidents_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_institutional_accounts$q$,$q$plone27_institutional_accounts_pkey$q$,'p',$q$PRIMARY KEY (account_id)$q$);
select pg_temp.k($q$plone27_invoices$q$,$q$plone27_invoices_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_issued_ids$q$,$q$plone27_issued_ids_pkey$q$,'p',$q$PRIMARY KEY (identifier)$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_junior_profiles$q$,$q$plone27_junior_profiles_pkey$q$,'p',$q$PRIMARY KEY (customer_id)$q$);
select pg_temp.k($q$plone27_juniors$q$,$q$plone27_juniors_pkey$q$,'p',$q$PRIMARY KEY (account_id)$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_late_accruals$q$,$q$plone27_late_accruals_pkey$q$,'p',$q$PRIMARY KEY (source, ref)$q$);
select pg_temp.k($q$plone27_ledger_entries$q$,$q$plone27_ledger_entries_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_numbering_formats$q$,$q$plone27_numbering_formats_pkey$q$,'p',$q$PRIMARY KEY (kind, version)$q$);
select pg_temp.k($q$plone27_outbox$q$,$q$plone27_outbox_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_payslips$q$,$q$plone27_payslips_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_plan_items$q$,$q$plone27_plan_items_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_policies$q$,$q$plone27_policies_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_products$q$,$q$plone27_products_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_rbu_bonuses$q$,$q$plone27_rbu_bonuses_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_reservations$q$,$q$plone27_reservations_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_sales$q$,$q$plone27_sales_pkey$q$,'p',$q$PRIMARY KEY (tx)$q$);
select pg_temp.k($q$plone27_scheduled$q$,$q$plone27_scheduled_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_setting_changes$q$,$q$plone27_setting_changes_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_settings$q$,$q$plone27_settings_pkey$q$,'p',$q$PRIMARY KEY (key)$q$);
select pg_temp.k($q$plone27_settlements$q$,$q$plone27_settlements_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_staff$q$,$q$plone27_staff_pkey$q$,'p',$q$PRIMARY KEY (user_id)$q$);
select pg_temp.k($q$plone27_subscriptions$q$,$q$plone27_subscriptions_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_tax_adjustments$q$,$q$plone27_tax_adjustments_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_tax_brackets$q$,$q$plone27_tax_brackets_pkey$q$,'p',$q$PRIMARY KEY (version_id, from_amount)$q$);
select pg_temp.k($q$plone27_tax_certificates$q$,$q$plone27_tax_certificates_pkey$q$,'p',$q$PRIMARY KEY (seq)$q$);
select pg_temp.k($q$plone27_tax_distribution$q$,$q$plone27_tax_distribution_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_tax_evaluations$q$,$q$plone27_tax_evaluations_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_tax_exemptions$q$,$q$plone27_tax_exemptions_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_tax_rule_versions$q$,$q$plone27_tax_rule_versions_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_tax_rules$q$,$q$plone27_tax_rules_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_transactions$q$,$q$plone27_transactions_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_webhooks$q$,$q$plone27_webhooks_pkey$q$,'p',$q$PRIMARY KEY (id)$q$);
select pg_temp.k($q$plone27_accounts$q$,$q$plone27_accounts_iban_key$q$,'u',$q$UNIQUE (iban)$q$);
select pg_temp.k($q$plone27_api_clients$q$,$q$plone27_api_clients_key_hash_key$q$,'u',$q$UNIQUE (key_hash)$q$);
select pg_temp.k($q$plone27_approvals$q$,$q$plone27_approvals_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_banks$q$,$q$plone27_banks_code_key$q$,'u',$q$UNIQUE (code)$q$);
select pg_temp.k($q$plone27_card_orders$q$,$q$plone27_card_orders_card_id_key$q$,'u',$q$UNIQUE (card_id)$q$);
select pg_temp.k($q$plone27_cards$q$,$q$plone27_cards_card_ref_key$q$,'u',$q$UNIQUE (card_ref)$q$);
select pg_temp.k($q$plone27_cards$q$,$q$plone27_cards_pan_hash_key$q$,'u',$q$UNIQUE (pan_hash)$q$);
select pg_temp.k($q$plone27_customers$q$,$q$plone27_customers_dip_key$q$,'u',$q$UNIQUE (dip)$q$);
select pg_temp.k($q$plone27_debts$q$,$q$plone27_debts_origin_key$q$,'u',$q$UNIQUE (origin)$q$);
select pg_temp.k($q$plone27_debts$q$,$q$plone27_debts_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_disputes$q$,$q$plone27_disputes_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_grants$q$,$q$plone27_grants_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_incidents$q$,$q$plone27_incidents_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_invoices$q$,$q$plone27_invoices_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_ref_key_key$q$,'u',$q$UNIQUE (ref_key)$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_invoice_ref_key$q$,'u',$q$UNIQUE (invoice_ref)$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_reimb_ref_key$q$,'u',$q$UNIQUE (reimb_ref)$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_transaction_id_key$q$,'u',$q$UNIQUE (transaction_id)$q$);
select pg_temp.k($q$plone27_payslips$q$,$q$plone27_payslips_contract_id_pay_date_key$q$,'u',$q$UNIQUE (contract_id, pay_date)$q$);
select pg_temp.k($q$plone27_plan_items$q$,$q$plone27_plan_items_plan_id_seq_key$q$,'u',$q$UNIQUE (plan_id, seq)$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_idem_key_key$q$,'u',$q$UNIQUE (idem_key)$q$);
select pg_temp.k($q$plone27_policies$q$,$q$plone27_policies_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_products$q$,$q$plone27_products_code_key$q$,'u',$q$UNIQUE (code)$q$);
select pg_temp.k($q$plone27_rbu_bonuses$q$,$q$plone27_rbu_bonuses_owner_user_week_start_key$q$,'u',$q$UNIQUE (owner_user, week_start)$q$);
select pg_temp.k($q$plone27_settlements$q$,$q$plone27_settlements_bank_id_period_from_period_to_key$q$,'u',$q$UNIQUE (bank_id, period_from, period_to)$q$);
select pg_temp.k($q$plone27_settlements$q$,$q$plone27_settlements_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_subscriptions$q$,$q$plone27_subscriptions_account_id_key$q$,'u',$q$UNIQUE (account_id)$q$);
select pg_temp.k($q$plone27_tax_adjustments$q$,$q$plone27_tax_adjustments_receipt_id_new_version_id_key$q$,'u',$q$UNIQUE (receipt_id, new_version_id)$q$);
select pg_temp.k($q$plone27_tax_adjustments$q$,$q$plone27_tax_adjustments_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_tax_certificates$q$,$q$plone27_tax_certificates_hash_key$q$,'u',$q$UNIQUE (hash)$q$);
select pg_temp.k($q$plone27_tax_certificates$q$,$q$plone27_tax_certificates_id_key$q$,'u',$q$UNIQUE (id)$q$);
select pg_temp.k($q$plone27_tax_evaluations$q$,$q$plone27_tax_evaluations_event_key_key$q$,'u',$q$UNIQUE (event_key)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_tax_rule_versions$q$,$q$plone27_tax_rule_versions_rule_id_version_key$q$,'u',$q$UNIQUE (rule_id, version)$q$);
select pg_temp.k($q$plone27_tax_rules$q$,$q$plone27_tax_rules_code_key$q$,'u',$q$UNIQUE (code)$q$);
select pg_temp.k($q$plone27_transactions$q$,$q$plone27_transactions_idempotency_key_key$q$,'u',$q$UNIQUE (idempotency_key)$q$);
select pg_temp.k($q$plone27_transactions$q$,$q$plone27_transactions_ref_key$q$,'u',$q$UNIQUE (ref)$q$);
select pg_temp.k($q$plone27_transactions$q$,$q$plone27_transactions_transfer_ref_key$q$,'u',$q$UNIQUE (transfer_ref)$q$);
select pg_temp.k($q$plone27_account_members$q$,$q$plone27_account_members_role_check$q$,'c',$q$CHECK ((role = ANY (ARRAY['holder'::text, 'coholder'::text, 'authorized'::text])))$q$);
select pg_temp.k($q$plone27_accounts$q$,$q$plone27_accounts_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['personal'::text, 'business'::text, 'shared'::text, 'junior'::text, 'system'::text])))$q$);
select pg_temp.k($q$plone27_accounts$q$,$q$plone27_accounts_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'blocked'::text, 'closed'::text])))$q$);
select pg_temp.k($q$plone27_activities$q$,$q$plone27_activities_category_check$q$,'c',$q$CHECK ((category = ANY (ARRAY['microactividad'::text, 'pequena'::text, 'mediana'::text, 'grande'::text, 'especial'::text])))$q$);
select pg_temp.k($q$plone27_activities$q$,$q$plone27_activities_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'closed'::text])))$q$);
select pg_temp.k($q$plone27_banks$q$,$q$banks_code4$q$,'c',$q$CHECK ((code ~ '^[0-9]{4}$'::text)) NOT VALID$q$);
select pg_temp.k($q$plone27_banks$q$,$q$plone27_banks_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['draft'::text, 'review'::text, 'active'::text, 'suspended'::text, 'closed'::text])))$q$);
select pg_temp.k($q$plone27_batch_items$q$,$q$plone27_batch_items_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_batch_items$q$,$q$plone27_batch_items_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['pending'::text, 'paid'::text, 'failed'::text])))$q$);
select pg_temp.k($q$plone27_batches$q$,$q$plone27_batches_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['payroll'::text, 'batch'::text])))$q$);
select pg_temp.k($q$plone27_batches$q$,$q$plone27_batches_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['open'::text, 'done'::text, 'partial'::text])))$q$);
select pg_temp.k($q$plone27_card_charges$q$,$q$plone27_card_charges_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_card_charges$q$,$q$plone27_card_charges_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['authorized'::text, 'billed'::text, 'settled'::text, 'released'::text])))$q$);
select pg_temp.k($q$plone27_card_designs$q$,$q$plone27_card_designs_elements_check$q$,'c',$q$CHECK ((NOT (elements ?| ARRAY['pan'::text, 'cvv'::text, 'chip'::text, 'banda'::text, 'antena'::text, 'stripe'::text, 'antenna'::text, 'limit'::text, 'status'::text, 'balance'::text])))$q$);
select pg_temp.k($q$plone27_card_designs$q$,$q$plone27_card_designs_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'review'::text, 'approved'::text, 'rejected'::text])))$q$);
select pg_temp.k($q$plone27_card_designs$q$,$q$plone27_card_designs_tier_check$q$,'c',$q$CHECK ((tier = ANY (ARRAY['free'::text, 'premium'::text, 'commissioned'::text, 'limited'::text])))$q$);
select pg_temp.k($q$plone27_card_orders$q$,$q$plone27_card_orders_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['ordered'::text, 'produced'::text, 'shipped'::text, 'activated'::text, 'cancelled'::text])))$q$);
select pg_temp.k($q$plone27_cards$q$,$q$plone27_cards_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['digital'::text, 'physical'::text, 'credit'::text])))$q$);
select pg_temp.k($q$plone27_cards$q$,$q$plone27_cards_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text, 'blocked'::text, 'closed'::text])))$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_full_time_check$q$,'c',$q$CHECK (full_time)$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_gross_monthly_check$q$,'c',$q$CHECK ((gross_monthly > (0)::numeric))$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_pay_day_check$q$,'c',$q$CHECK (((pay_day >= 1) AND (pay_day <= 28)))$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'ended'::text])))$q$);
select pg_temp.k($q$plone27_customers$q$,$q$plone27_customers_dip_check$q$,'c',$q$CHECK ((dip ~ '^[A-Z0-9-]{4,24}$'::text))$q$);
select pg_temp.k($q$plone27_customers$q$,$q$plone27_customers_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'blocked'::text])))$q$);
select pg_temp.k($q$plone27_disputes$q$,$q$plone27_disputes_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['open'::text, 'upheld'::text, 'rejected'::text, 'withdrawn'::text])))$q$);
select pg_temp.k($q$plone27_disputes$q$,$q$plone27_disputes_subject_type_check$q$,'c',$q$CHECK ((subject_type = ANY (ARRAY['receipt'::text, 'debt'::text])))$q$);
select pg_temp.k($q$plone27_fee_rules$q$,$q$plone27_fee_rules_method_check$q$,'c',$q$CHECK ((method = ANY (ARRAY['percent'::text, 'fixed'::text])))$q$);
select pg_temp.k($q$plone27_fee_rules$q$,$q$plone27_fee_rules_payer_check$q$,'c',$q$CHECK ((payer = ANY (ARRAY['user'::text, 'bank'::text, 'both'::text, 'exempt'::text])))$q$);
select pg_temp.k($q$plone27_grant_programs$q$,$q$plone27_grant_programs_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['subvencion'::text, 'bono'::text])))$q$);
select pg_temp.k($q$plone27_institutional_accounts$q$,$q$plone27_institutional_accounts_motivo_check$q$,'c',$q$CHECK ((length(motivo) >= 10))$q$);
select pg_temp.k($q$plone27_invoices$q$,$q$plone27_invoices_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_invoices$q$,$q$plone27_invoices_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['issued'::text, 'paid'::text, 'void'::text])))$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['cobro_comercial_sin_iva'::text, 'patron_comercial_personal'::text, 'fraccionamiento'::text])))$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_propuesta_accion_check$q$,'c',$q$CHECK ((propuesta_accion = ANY (ARRAY['regularizar'::text, 'descartar'::text])))$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_severity_check$q$,'c',$q$CHECK ((severity = ANY (ARRAY['alta'::text, 'media'::text, 'baja'::text])))$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['abierto'::text, 'regularizado'::text, 'descartado'::text])))$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'paid'::text, 'rejected'::text])))$q$);
select pg_temp.k($q$plone27_late_accruals$q$,$q$plone27_late_accruals_source_check$q$,'c',$q$CHECK ((source = ANY (ARRAY['item'::text, 'receipt'::text])))$q$);
select pg_temp.k($q$plone27_ledger_entries$q$,$q$plone27_ledger_entries_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_ledger_entries$q$,$q$plone27_ledger_entries_direction_check$q$,'c',$q$CHECK ((direction = ANY (ARRAY['debit'::text, 'credit'::text])))$q$);
select pg_temp.k($q$plone27_numbering_formats$q$,$q$plone27_numbering_formats_prefix_check$q$,'c',$q$CHECK ((prefix ~ '^PL27-[A-Z]{3}-$'::text))$q$);
select pg_temp.k($q$plone27_numbering_formats$q$,$q$plone27_numbering_formats_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text])))$q$);
select pg_temp.k($q$plone27_numbering_formats$q$,$q$plone27_numbering_formats_width_check$q$,'c',$q$CHECK (((width >= 4) AND (width <= 15)))$q$);
select pg_temp.k($q$plone27_outbox$q$,$q$plone27_outbox_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text])))$q$);
select pg_temp.k($q$plone27_plan_items$q$,$q$plone27_plan_items_interest_part_check$q$,'c',$q$CHECK ((interest_part >= (0)::numeric))$q$);
select pg_temp.k($q$plone27_plan_items$q$,$q$plone27_plan_items_principal_part_check$q$,'c',$q$CHECK ((principal_part >= (0)::numeric))$q$);
select pg_temp.k($q$plone27_plan_items$q$,$q$plone27_plan_items_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['pending'::text, 'paid'::text])))$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_anchor_day_check$q$,'c',$q$CHECK (((anchor_day >= 1) AND (anchor_day <= 31)))$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_annual_rate_pct_check$q$,'c',$q$CHECK ((annual_rate_pct >= (0)::numeric))$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_check$q$,'c',$q$CHECK ((((kind = 'installment'::text) AND (installments IS NOT NULL) AND (lender_account IS NOT NULL)) OR ((kind = 'subscription'::text) AND (installments IS NULL) AND (lender_account IS NULL))))$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_installments_check$q$,'c',$q$CHECK ((installments > 0))$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['installment'::text, 'subscription'::text])))$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_principal_check$q$,'c',$q$CHECK ((principal > (0)::numeric))$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'past_due'::text, 'completed'::text, 'cancelled'::text])))$q$);
select pg_temp.k($q$plone27_policies$q$,$q$plone27_policies_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['penalty'::text, 'dispute'::text, 'debt_terms'::text])))$q$);
select pg_temp.k($q$plone27_policies$q$,$q$plone27_policies_scope_check$q$,'c',$q$CHECK ((scope = ANY (ARRAY['global'::text, 'bank'::text, 'customer'::text, 'dip'::text])))$q$);
select pg_temp.k($q$plone27_policies$q$,$q$plone27_policies_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text, 'retired'::text])))$q$);
select pg_temp.k($q$plone27_products$q$,$q$plone27_products_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['account_personal'::text, 'account_business'::text, 'account_shared'::text, 'account_junior'::text, 'card_digital'::text, 'card_physical'::text, 'card_credit'::text, 'internal_credit'::text, 'service'::text])))$q$);
select pg_temp.k($q$plone27_products$q$,$q$plone27_products_monthly_fee_check$q$,'c',$q$CHECK ((monthly_fee >= (0)::numeric))$q$);
select pg_temp.k($q$plone27_products$q$,$q$plone27_products_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'retired'::text])))$q$);
select pg_temp.k($q$plone27_products$q$,$q$products_junior_compat$q$,'c',$q$CHECK (((kind <> 'account_junior'::text) OR ((COALESCE(credit_limit, (0)::numeric) = (0)::numeric) AND (interest_rate = (0)::numeric) AND requires_guardian)))$q$);
select pg_temp.k($q$plone27_rbu_bonuses$q$,$q$plone27_rbu_bonuses_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_rbu_bonuses$q$,$q$plone27_rbu_bonuses_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['available'::text, 'claimed'::text, 'expired'::text])))$q$);
select pg_temp.k($q$plone27_reservations$q$,$q$plone27_reservations_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_reservations$q$,$q$plone27_reservations_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'released'::text])))$q$);
select pg_temp.k($q$plone27_sales$q$,$q$plone27_sales_origin_check$q$,'c',$q$CHECK ((origin = ANY (ARRAY['plataforma'::text, 'regularizada'::text])))$q$);
select pg_temp.k($q$plone27_scheduled$q$,$q$plone27_scheduled_amount_check$q$,'c',$q$CHECK ((amount > (0)::numeric))$q$);
select pg_temp.k($q$plone27_scheduled$q$,$q$plone27_scheduled_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'done'::text, 'cancelled'::text])))$q$);
select pg_temp.k($q$plone27_setting_changes$q$,$q$plone27_setting_changes_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['pending'::text, 'applied'::text, 'rejected'::text])))$q$);
select pg_temp.k($q$plone27_settings$q$,$q$plone27_settings_vtype_check$q$,'c',$q$CHECK ((vtype = ANY (ARRAY['number'::text, 'boolean'::text, 'text'::text, 'enum'::text])))$q$);
select pg_temp.k($q$plone27_staff$q$,$q$plone27_staff_role_check$q$,'c',$q$CHECK ((role = ANY (ARRAY['admin'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'auditor'::text, 'aprobador'::text])))$q$);
select pg_temp.k($q$plone27_subscriptions$q$,$q$plone27_subscriptions_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['active'::text, 'past_due'::text, 'expired'::text, 'cancelled'::text])))$q$);
select pg_temp.k($q$plone27_tax_adjustments$q$,$q$plone27_tax_adjustments_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['simulated'::text, 'approved'::text, 'executed'::text])))$q$);
select pg_temp.k($q$plone27_tax_certificates$q$,$q$plone27_tax_certificates_kind_check$q$,'c',$q$CHECK ((kind = ANY (ARRAY['recibo'::text, 'regularizacion'::text, 'recargo'::text, 'rectificacion'::text])))$q$);
select pg_temp.k($q$plone27_tax_distribution$q$,$q$plone27_tax_distribution_pct_check$q$,'c',$q$CHECK (((pct > (0)::numeric) AND (pct <= (100)::numeric)))$q$);
select pg_temp.k($q$plone27_tax_evaluations$q$,$q$plone27_tax_evaluations_pathway_check$q$,'c',$q$CHECK ((pathway = ANY (ARRAY['automatica'::text, 'periodica'::text, 'recibo'::text, 'declaracion'::text, 'regularizacion'::text, 'liquidacion_bancaria'::text, 'devolucion'::text, 'revision_manual'::text])))$q$);
select pg_temp.k($q$plone27_tax_evaluations$q$,$q$plone27_tax_evaluations_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['calculated'::text, 'review'::text, 'exempt'::text])))$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['issued'::text, 'partial'::text, 'paid'::text, 'rectified'::text])))$q$);
select pg_temp.k($q$plone27_tax_rule_versions$q$,$q$plone27_tax_rule_versions_method_check$q$,'c',$q$CHECK ((method = ANY (ARRAY['percent'::text, 'fixed'::text, 'brackets'::text, 'bracket_flat'::text])))$q$);
select pg_temp.k($q$plone27_tax_rule_versions$q$,$q$plone27_tax_rule_versions_retro_mode_check$q$,'c',$q$CHECK ((retro_mode = ANY (ARRAY['prohibited'::text, 'simulation'::text, 'automatic'::text])))$q$);
select pg_temp.k($q$plone27_tax_rule_versions$q$,$q$plone27_tax_rule_versions_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['draft'::text, 'published'::text])))$q$);
select pg_temp.k($q$plone27_transactions$q$,$q$plone27_transactions_status_check$q$,'c',$q$CHECK ((status = ANY (ARRAY['posted'::text, 'reversed'::text])))$q$);
select pg_temp.k($q$plone27_webhooks$q$,$q$plone27_webhooks_url_check$q$,'c',$q$CHECK ((url ~ '^https://'::text))$q$);
select pg_temp.k($q$plone27_account_members$q$,$q$plone27_account_members_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_accounts$q$,$q$plone27_accounts_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_accounts$q$,$q$plone27_accounts_customer_id_fkey$q$,'f',$q$FOREIGN KEY (customer_id) REFERENCES plone27_customers(id)$q$);
select pg_temp.k($q$plone27_accounts$q$,$q$plone27_accounts_product_id_fkey$q$,'f',$q$FOREIGN KEY (product_id) REFERENCES plone27_products(id)$q$);
select pg_temp.k($q$plone27_activities$q$,$q$plone27_activities_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_api_clients$q$,$q$plone27_api_clients_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_api_usage$q$,$q$plone27_api_usage_client_id_fkey$q$,'f',$q$FOREIGN KEY (client_id) REFERENCES plone27_api_clients(id)$q$);
select pg_temp.k($q$plone27_bank_settings$q$,$q$plone27_bank_settings_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_bank_settings$q$,$q$plone27_bank_settings_key_fkey$q$,'f',$q$FOREIGN KEY (key) REFERENCES plone27_settings(key)$q$);
select pg_temp.k($q$plone27_banks$q$,$q$plone27_banks_main_account_fkey$q$,'f',$q$FOREIGN KEY (main_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_banks$q$,$q$plone27_banks_tax_account_fkey$q$,'f',$q$FOREIGN KEY (tax_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_batch_items$q$,$q$plone27_batch_items_batch_id_fkey$q$,'f',$q$FOREIGN KEY (batch_id) REFERENCES plone27_batches(id)$q$);
select pg_temp.k($q$plone27_batch_items$q$,$q$plone27_batch_items_to_account_fkey$q$,'f',$q$FOREIGN KEY (to_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_batches$q$,$q$plone27_batches_from_account_fkey$q$,'f',$q$FOREIGN KEY (from_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_card_charges$q$,$q$plone27_card_charges_card_id_fkey$q$,'f',$q$FOREIGN KEY (card_id) REFERENCES plone27_cards(id)$q$);
select pg_temp.k($q$plone27_card_charges$q$,$q$plone27_card_charges_merchant_account_fkey$q$,'f',$q$FOREIGN KEY (merchant_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_card_charges$q$,$q$plone27_card_charges_reservation_id_fkey$q$,'f',$q$FOREIGN KEY (reservation_id) REFERENCES plone27_reservations(id)$q$);
select pg_temp.k($q$plone27_card_designs$q$,$q$plone27_card_designs_revenue_account_fkey$q$,'f',$q$FOREIGN KEY (revenue_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_card_orders$q$,$q$plone27_card_orders_card_id_fkey$q$,'f',$q$FOREIGN KEY (card_id) REFERENCES plone27_cards(id)$q$);
select pg_temp.k($q$plone27_cards$q$,$q$plone27_cards_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_cards$q$,$q$plone27_cards_design_id_fkey$q$,'f',$q$FOREIGN KEY (design_id) REFERENCES plone27_card_designs(id)$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_employer_account_fkey$q$,'f',$q$FOREIGN KEY (employer_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_contracts$q$,$q$plone27_contracts_worker_account_fkey$q$,'f',$q$FOREIGN KEY (worker_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_customers$q$,$q$plone27_customers_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_debts$q$,$q$plone27_debts_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_debts$q$,$q$plone27_debts_creditor_account_fkey$q$,'f',$q$FOREIGN KEY (creditor_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_design_purchases$q$,$q$plone27_design_purchases_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_design_purchases$q$,$q$plone27_design_purchases_design_id_fkey$q$,'f',$q$FOREIGN KEY (design_id) REFERENCES plone27_card_designs(id)$q$);
select pg_temp.k($q$plone27_disputes$q$,$q$plone27_disputes_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_fee_rules$q$,$q$plone27_fee_rules_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_fee_rules$q$,$q$plone27_fee_rules_bank_pay_account_fkey$q$,'f',$q$FOREIGN KEY (bank_pay_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_fee_rules$q$,$q$plone27_fee_rules_beneficiary_account_fkey$q$,'f',$q$FOREIGN KEY (beneficiary_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_grant_programs$q$,$q$plone27_grant_programs_funding_account_fkey$q$,'f',$q$FOREIGN KEY (funding_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_grants$q$,$q$plone27_grants_beneficiary_account_fkey$q$,'f',$q$FOREIGN KEY (beneficiary_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_grants$q$,$q$plone27_grants_program_id_fkey$q$,'f',$q$FOREIGN KEY (program_id) REFERENCES plone27_grant_programs(id)$q$);
select pg_temp.k($q$plone27_institutional_accounts$q$,$q$plone27_institutional_accounts_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_invoices$q$,$q$plone27_invoices_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_counterpart_account_fkey$q$,'f',$q$FOREIGN KEY (counterpart_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_receipt_id_fkey$q$,'f',$q$FOREIGN KEY (receipt_id) REFERENCES plone27_tax_receipts(id)$q$);
select pg_temp.k($q$plone27_iva_findings$q$,$q$plone27_iva_findings_tx_fkey$q$,'f',$q$FOREIGN KEY (tx) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_junior_profiles$q$,$q$plone27_junior_profiles_customer_id_fkey$q$,'f',$q$FOREIGN KEY (customer_id) REFERENCES plone27_customers(id)$q$);
select pg_temp.k($q$plone27_juniors$q$,$q$plone27_juniors_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_grant_id_fkey$q$,'f',$q$FOREIGN KEY (grant_id) REFERENCES plone27_grants(id)$q$);
select pg_temp.k($q$plone27_justifications$q$,$q$plone27_justifications_transaction_id_fkey$q$,'f',$q$FOREIGN KEY (transaction_id) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_ledger_entries$q$,$q$plone27_ledger_entries_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_ledger_entries$q$,$q$plone27_ledger_entries_transaction_id_fkey$q$,'f',$q$FOREIGN KEY (transaction_id) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_payslips$q$,$q$plone27_payslips_contract_id_fkey$q$,'f',$q$FOREIGN KEY (contract_id) REFERENCES plone27_contracts(id)$q$);
select pg_temp.k($q$plone27_payslips$q$,$q$plone27_payslips_tx_fkey$q$,'f',$q$FOREIGN KEY (tx) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_plan_items$q$,$q$plone27_plan_items_paid_tx_fkey$q$,'f',$q$FOREIGN KEY (paid_tx) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_plan_items$q$,$q$plone27_plan_items_plan_id_fkey$q$,'f',$q$FOREIGN KEY (plan_id) REFERENCES plone27_plans(id)$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_beneficiary_account_fkey$q$,'f',$q$FOREIGN KEY (beneficiary_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_debtor_account_fkey$q$,'f',$q$FOREIGN KEY (debtor_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_plans$q$,$q$plone27_plans_lender_account_fkey$q$,'f',$q$FOREIGN KEY (lender_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_policies$q$,$q$plone27_policies_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_policies$q$,$q$plone27_policies_customer_id_fkey$q$,'f',$q$FOREIGN KEY (customer_id) REFERENCES plone27_customers(id)$q$);
select pg_temp.k($q$plone27_products$q$,$q$plone27_products_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_products$q$,$q$plone27_products_fee_account_fkey$q$,'f',$q$FOREIGN KEY (fee_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_rbu_bonuses$q$,$q$plone27_rbu_bonuses_claimed_tx_fkey$q$,'f',$q$FOREIGN KEY (claimed_tx) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_rbu_bonuses$q$,$q$plone27_rbu_bonuses_wallet_account_fkey$q$,'f',$q$FOREIGN KEY (wallet_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_reservations$q$,$q$plone27_reservations_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_sales$q$,$q$plone27_sales_buyer_account_fkey$q$,'f',$q$FOREIGN KEY (buyer_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_sales$q$,$q$plone27_sales_seller_account_fkey$q$,'f',$q$FOREIGN KEY (seller_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_sales$q$,$q$plone27_sales_tx_fkey$q$,'f',$q$FOREIGN KEY (tx) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_scheduled$q$,$q$plone27_scheduled_from_account_fkey$q$,'f',$q$FOREIGN KEY (from_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_scheduled$q$,$q$plone27_scheduled_to_account_fkey$q$,'f',$q$FOREIGN KEY (to_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_setting_changes$q$,$q$plone27_setting_changes_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_setting_changes$q$,$q$plone27_setting_changes_key_fkey$q$,'f',$q$FOREIGN KEY (key) REFERENCES plone27_settings(key)$q$);
select pg_temp.k($q$plone27_settlements$q$,$q$plone27_settlements_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_staff$q$,$q$plone27_staff_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_staff$q$,$q$plone27_staff_user_id_fkey$q$,'f',$q$FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE$q$);
select pg_temp.k($q$plone27_subscriptions$q$,$q$plone27_subscriptions_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_subscriptions$q$,$q$plone27_subscriptions_last_tx_fkey$q$,'f',$q$FOREIGN KEY (last_tx) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_subscriptions$q$,$q$plone27_subscriptions_product_id_fkey$q$,'f',$q$FOREIGN KEY (product_id) REFERENCES plone27_products(id)$q$);
select pg_temp.k($q$plone27_tax_adjustments$q$,$q$plone27_tax_adjustments_new_version_id_fkey$q$,'f',$q$FOREIGN KEY (new_version_id) REFERENCES plone27_tax_rule_versions(id)$q$);
select pg_temp.k($q$plone27_tax_adjustments$q$,$q$plone27_tax_adjustments_receipt_id_fkey$q$,'f',$q$FOREIGN KEY (receipt_id) REFERENCES plone27_tax_receipts(id)$q$);
select pg_temp.k($q$plone27_tax_brackets$q$,$q$plone27_tax_brackets_version_id_fkey$q$,'f',$q$FOREIGN KEY (version_id) REFERENCES plone27_tax_rule_versions(id)$q$);
select pg_temp.k($q$plone27_tax_certificates$q$,$q$plone27_tax_certificates_reemplaza_fkey$q$,'f',$q$FOREIGN KEY (reemplaza) REFERENCES plone27_tax_certificates(id)$q$);
select pg_temp.k($q$plone27_tax_certificates$q$,$q$plone27_tax_certificates_version_id_fkey$q$,'f',$q$FOREIGN KEY (version_id) REFERENCES plone27_tax_rule_versions(id)$q$);
select pg_temp.k($q$plone27_tax_distribution$q$,$q$plone27_tax_distribution_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_tax_distribution$q$,$q$plone27_tax_distribution_rule_id_fkey$q$,'f',$q$FOREIGN KEY (rule_id) REFERENCES plone27_tax_rules(id)$q$);
select pg_temp.k($q$plone27_tax_evaluations$q$,$q$plone27_tax_evaluations_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_tax_evaluations$q$,$q$plone27_tax_evaluations_rule_id_fkey$q$,'f',$q$FOREIGN KEY (rule_id) REFERENCES plone27_tax_rules(id)$q$);
select pg_temp.k($q$plone27_tax_evaluations$q$,$q$plone27_tax_evaluations_rule_version_id_fkey$q$,'f',$q$FOREIGN KEY (rule_version_id) REFERENCES plone27_tax_rule_versions(id)$q$);
select pg_temp.k($q$plone27_tax_exemptions$q$,$q$plone27_tax_exemptions_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_tax_exemptions$q$,$q$plone27_tax_exemptions_rule_id_fkey$q$,'f',$q$FOREIGN KEY (rule_id) REFERENCES plone27_tax_rules(id)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_account_id_fkey$q$,'f',$q$FOREIGN KEY (account_id) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_evaluation_id_fkey$q$,'f',$q$FOREIGN KEY (evaluation_id) REFERENCES plone27_tax_evaluations(id)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_obligor_account_fkey$q$,'f',$q$FOREIGN KEY (obligor_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_original_receipt_fkey$q$,'f',$q$FOREIGN KEY (original_receipt) REFERENCES plone27_tax_receipts(id)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_paid_tx_fkey$q$,'f',$q$FOREIGN KEY (paid_tx) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_tax_receipts$q$,$q$plone27_tax_receipts_rule_version_id_fkey$q$,'f',$q$FOREIGN KEY (rule_version_id) REFERENCES plone27_tax_rule_versions(id)$q$);
select pg_temp.k($q$plone27_tax_rule_versions$q$,$q$plone27_tax_rule_versions_rule_id_fkey$q$,'f',$q$FOREIGN KEY (rule_id) REFERENCES plone27_tax_rules(id)$q$);
select pg_temp.k($q$plone27_tax_rule_versions$q$,$q$plone27_tax_rule_versions_scope_bank_fkey$q$,'f',$q$FOREIGN KEY (scope_bank) REFERENCES plone27_banks(id)$q$);
select pg_temp.k($q$plone27_tax_rules$q$,$q$plone27_tax_rules_collector_account_fkey$q$,'f',$q$FOREIGN KEY (collector_account) REFERENCES plone27_accounts(id)$q$);
select pg_temp.k($q$plone27_transactions$q$,$q$plone27_transactions_reverses_fkey$q$,'f',$q$FOREIGN KEY (reverses) REFERENCES plone27_transactions(id)$q$);
select pg_temp.k($q$plone27_webhooks$q$,$q$plone27_webhooks_bank_id_fkey$q$,'f',$q$FOREIGN KEY (bank_id) REFERENCES plone27_banks(id)$q$);
-- ===== 6. ÍNDICES =====
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_accounts_bank_id ON public.plone27_accounts USING btree (bank_id)$q$, $q$índice ix_accounts_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_accounts_customer_id ON public.plone27_accounts USING btree (customer_id)$q$, $q$índice ix_accounts_customer_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_accounts_product_id ON public.plone27_accounts USING btree (product_id)$q$, $q$índice ix_accounts_product_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_accounts_status ON public.plone27_accounts USING btree (status)$q$, $q$índice ix_accounts_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_activities_account_id ON public.plone27_activities USING btree (account_id)$q$, $q$índice ix_activities_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_api_clients_bank_id ON public.plone27_api_clients USING btree (bank_id)$q$, $q$índice ix_api_clients_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_approvals_at_d ON public.plone27_approvals USING btree (at DESC)$q$, $q$índice ix_approvals_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_audit_log_at_d ON public.plone27_audit_log USING btree (at DESC)$q$, $q$índice ix_audit_log_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_audit_log_entity ON public.plone27_audit_log USING btree (entity)$q$, $q$índice ix_audit_log_entity$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_bank_settings_key ON public.plone27_bank_settings USING btree (key)$q$, $q$índice ix_bank_settings_key$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_banks_main_account ON public.plone27_banks USING btree (main_account)$q$, $q$índice ix_banks_main_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_banks_status ON public.plone27_banks USING btree (status)$q$, $q$índice ix_banks_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_banks_tax_account ON public.plone27_banks USING btree (tax_account)$q$, $q$índice ix_banks_tax_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_batch_items_batch_id ON public.plone27_batch_items USING btree (batch_id)$q$, $q$índice ix_batch_items_batch_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_batch_items_to_account ON public.plone27_batch_items USING btree (to_account)$q$, $q$índice ix_batch_items_to_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_batches_from_account ON public.plone27_batches USING btree (from_account)$q$, $q$índice ix_batches_from_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_batches_status ON public.plone27_batches USING btree (status)$q$, $q$índice ix_batches_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_card_charges_card_id ON public.plone27_card_charges USING btree (card_id)$q$, $q$índice ix_card_charges_card_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_card_charges_merchant_account ON public.plone27_card_charges USING btree (merchant_account)$q$, $q$índice ix_card_charges_merchant_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_card_charges_reservation_id ON public.plone27_card_charges USING btree (reservation_id)$q$, $q$índice ix_card_charges_reservation_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_card_designs_revenue_account ON public.plone27_card_designs USING btree (revenue_account)$q$, $q$índice ix_card_designs_revenue_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_cards_account_id ON public.plone27_cards USING btree (account_id)$q$, $q$índice ix_cards_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_cards_design_id ON public.plone27_cards USING btree (design_id)$q$, $q$índice ix_cards_design_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_cards_status ON public.plone27_cards USING btree (status)$q$, $q$índice ix_cards_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_contracts_bank_id ON public.plone27_contracts USING btree (bank_id)$q$, $q$índice ix_contracts_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_contracts_employer_account ON public.plone27_contracts USING btree (employer_account)$q$, $q$índice ix_contracts_employer_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_contracts_status ON public.plone27_contracts USING btree (status)$q$, $q$índice ix_contracts_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_contracts_worker_account ON public.plone27_contracts USING btree (worker_account)$q$, $q$índice ix_contracts_worker_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_customers_bank_id ON public.plone27_customers USING btree (bank_id)$q$, $q$índice ix_customers_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_debts_account_id ON public.plone27_debts USING btree (account_id)$q$, $q$índice ix_debts_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_debts_creditor_account ON public.plone27_debts USING btree (creditor_account)$q$, $q$índice ix_debts_creditor_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_design_purchases_account_id ON public.plone27_design_purchases USING btree (account_id)$q$, $q$índice ix_design_purchases_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_disputes_account_id ON public.plone27_disputes USING btree (account_id)$q$, $q$índice ix_disputes_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_disputes_opened_at_d ON public.plone27_disputes USING btree (opened_at DESC)$q$, $q$índice ix_disputes_opened_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_disputes_status ON public.plone27_disputes USING btree (status)$q$, $q$índice ix_disputes_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_fee_rules_bank_id ON public.plone27_fee_rules USING btree (bank_id)$q$, $q$índice ix_fee_rules_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_fee_rules_bank_pay_account ON public.plone27_fee_rules USING btree (bank_pay_account)$q$, $q$índice ix_fee_rules_bank_pay_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_fee_rules_beneficiary_account ON public.plone27_fee_rules USING btree (beneficiary_account)$q$, $q$índice ix_fee_rules_beneficiary_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_grant_programs_funding_account ON public.plone27_grant_programs USING btree (funding_account)$q$, $q$índice ix_grant_programs_funding_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_grants_beneficiary_account ON public.plone27_grants USING btree (beneficiary_account)$q$, $q$índice ix_grants_beneficiary_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_grants_program_id ON public.plone27_grants USING btree (program_id)$q$, $q$índice ix_grants_program_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_incidents_at_d ON public.plone27_incidents USING btree (at DESC)$q$, $q$índice ix_incidents_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_incidents_status ON public.plone27_incidents USING btree (status)$q$, $q$índice ix_incidents_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_invoices_account_id ON public.plone27_invoices USING btree (account_id)$q$, $q$índice ix_invoices_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_iva_findings_account_id ON public.plone27_iva_findings USING btree (account_id)$q$, $q$índice ix_iva_findings_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_iva_findings_counterpart_account ON public.plone27_iva_findings USING btree (counterpart_account)$q$, $q$índice ix_iva_findings_counterpart_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_iva_findings_detected_at_d ON public.plone27_iva_findings USING btree (detected_at DESC)$q$, $q$índice ix_iva_findings_detected_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_iva_findings_receipt_id ON public.plone27_iva_findings USING btree (receipt_id)$q$, $q$índice ix_iva_findings_receipt_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_iva_findings_status ON public.plone27_iva_findings USING btree (status)$q$, $q$índice ix_iva_findings_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_iva_findings_tx ON public.plone27_iva_findings USING btree (tx)$q$, $q$índice ix_iva_findings_tx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_justifications_grant_id ON public.plone27_justifications USING btree (grant_id)$q$, $q$índice ix_justifications_grant_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_ledger_entries_created_at_d ON public.plone27_ledger_entries USING btree (created_at DESC)$q$, $q$índice ix_ledger_entries_created_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_outbox_created_at ON public.plone27_outbox USING btree (created_at)$q$, $q$índice ix_outbox_created_at$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_outbox_status ON public.plone27_outbox USING btree (status)$q$, $q$índice ix_outbox_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_payslips_tx ON public.plone27_payslips USING btree (tx)$q$, $q$índice ix_payslips_tx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_plan_items_paid_tx ON public.plone27_plan_items USING btree (paid_tx)$q$, $q$índice ix_plan_items_paid_tx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_plan_items_status ON public.plone27_plan_items USING btree (status)$q$, $q$índice ix_plan_items_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_plans_bank_id ON public.plone27_plans USING btree (bank_id)$q$, $q$índice ix_plans_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_plans_beneficiary_account ON public.plone27_plans USING btree (beneficiary_account)$q$, $q$índice ix_plans_beneficiary_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_plans_debtor_account ON public.plone27_plans USING btree (debtor_account)$q$, $q$índice ix_plans_debtor_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_plans_lender_account ON public.plone27_plans USING btree (lender_account)$q$, $q$índice ix_plans_lender_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_plans_status ON public.plone27_plans USING btree (status)$q$, $q$índice ix_plans_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_policies_bank_id ON public.plone27_policies USING btree (bank_id)$q$, $q$índice ix_policies_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_policies_created_at_d ON public.plone27_policies USING btree (created_at DESC)$q$, $q$índice ix_policies_created_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_policies_customer_id ON public.plone27_policies USING btree (customer_id)$q$, $q$índice ix_policies_customer_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_products_bank_id ON public.plone27_products USING btree (bank_id)$q$, $q$índice ix_products_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_products_fee_account ON public.plone27_products USING btree (fee_account)$q$, $q$índice ix_products_fee_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_rbu_bonuses_claimed_tx ON public.plone27_rbu_bonuses USING btree (claimed_tx)$q$, $q$índice ix_rbu_bonuses_claimed_tx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_rbu_bonuses_status ON public.plone27_rbu_bonuses USING btree (status)$q$, $q$índice ix_rbu_bonuses_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_rbu_bonuses_wallet_account ON public.plone27_rbu_bonuses USING btree (wallet_account)$q$, $q$índice ix_rbu_bonuses_wallet_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_reservations_account_id ON public.plone27_reservations USING btree (account_id)$q$, $q$índice ix_reservations_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_sales_buyer_account ON public.plone27_sales USING btree (buyer_account)$q$, $q$índice ix_sales_buyer_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_sales_seller_account ON public.plone27_sales USING btree (seller_account)$q$, $q$índice ix_sales_seller_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_scheduled_from_account ON public.plone27_scheduled USING btree (from_account)$q$, $q$índice ix_scheduled_from_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_scheduled_status ON public.plone27_scheduled USING btree (status)$q$, $q$índice ix_scheduled_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_scheduled_to_account ON public.plone27_scheduled USING btree (to_account)$q$, $q$índice ix_scheduled_to_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_setting_changes_bank_id ON public.plone27_setting_changes USING btree (bank_id)$q$, $q$índice ix_setting_changes_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_setting_changes_key ON public.plone27_setting_changes USING btree (key)$q$, $q$índice ix_setting_changes_key$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_setting_changes_status ON public.plone27_setting_changes USING btree (status)$q$, $q$índice ix_setting_changes_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_staff_bank_id ON public.plone27_staff USING btree (bank_id)$q$, $q$índice ix_staff_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_subscriptions_last_tx ON public.plone27_subscriptions USING btree (last_tx)$q$, $q$índice ix_subscriptions_last_tx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_subscriptions_period_end ON public.plone27_subscriptions USING btree (period_end)$q$, $q$índice ix_subscriptions_period_end$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_subscriptions_product_id ON public.plone27_subscriptions USING btree (product_id)$q$, $q$índice ix_subscriptions_product_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_adjustments_new_version_id ON public.plone27_tax_adjustments USING btree (new_version_id)$q$, $q$índice ix_tax_adjustments_new_version_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_certificates_reemplaza ON public.plone27_tax_certificates USING btree (reemplaza)$q$, $q$índice ix_tax_certificates_reemplaza$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_certificates_subject_id ON public.plone27_tax_certificates USING btree (subject_id)$q$, $q$índice ix_tax_certificates_subject_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_certificates_version_id ON public.plone27_tax_certificates USING btree (version_id)$q$, $q$índice ix_tax_certificates_version_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_distribution_account_id ON public.plone27_tax_distribution USING btree (account_id)$q$, $q$índice ix_tax_distribution_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_distribution_rule_id ON public.plone27_tax_distribution USING btree (rule_id)$q$, $q$índice ix_tax_distribution_rule_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_evaluations_account_id ON public.plone27_tax_evaluations USING btree (account_id)$q$, $q$índice ix_tax_evaluations_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_evaluations_rule_id ON public.plone27_tax_evaluations USING btree (rule_id)$q$, $q$índice ix_tax_evaluations_rule_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_evaluations_rule_version_id ON public.plone27_tax_evaluations USING btree (rule_version_id)$q$, $q$índice ix_tax_evaluations_rule_version_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_exemptions_account_id ON public.plone27_tax_exemptions USING btree (account_id)$q$, $q$índice ix_tax_exemptions_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_exemptions_rule_id ON public.plone27_tax_exemptions USING btree (rule_id)$q$, $q$índice ix_tax_exemptions_rule_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_account_id ON public.plone27_tax_receipts USING btree (account_id)$q$, $q$índice ix_tax_receipts_account_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_created_at_d ON public.plone27_tax_receipts USING btree (created_at DESC)$q$, $q$índice ix_tax_receipts_created_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_due_date ON public.plone27_tax_receipts USING btree (due_date)$q$, $q$índice ix_tax_receipts_due_date$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_evaluation_id ON public.plone27_tax_receipts USING btree (evaluation_id)$q$, $q$índice ix_tax_receipts_evaluation_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_obligor_account ON public.plone27_tax_receipts USING btree (obligor_account)$q$, $q$índice ix_tax_receipts_obligor_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_original_receipt ON public.plone27_tax_receipts USING btree (original_receipt)$q$, $q$índice ix_tax_receipts_original_receipt$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_paid_tx ON public.plone27_tax_receipts USING btree (paid_tx)$q$, $q$índice ix_tax_receipts_paid_tx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_rule_version_id ON public.plone27_tax_receipts USING btree (rule_version_id)$q$, $q$índice ix_tax_receipts_rule_version_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_receipts_status ON public.plone27_tax_receipts USING btree (status)$q$, $q$índice ix_tax_receipts_status$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_rule_versions_scope_bank ON public.plone27_tax_rule_versions USING btree (scope_bank)$q$, $q$índice ix_tax_rule_versions_scope_bank$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_tax_rules_collector_account ON public.plone27_tax_rules USING btree (collector_account)$q$, $q$índice ix_tax_rules_collector_account$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_transactions_created_at_d ON public.plone27_transactions USING btree (created_at DESC)$q$, $q$índice ix_transactions_created_at_d$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_transactions_reverses ON public.plone27_transactions USING btree (reverses)$q$, $q$índice ix_transactions_reverses$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS ix_webhooks_bank_id ON public.plone27_webhooks USING btree (bank_id)$q$, $q$índice ix_webhooks_bank_id$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS plone27_cert_subject_idx ON public.plone27_tax_certificates USING btree (subject_id, seq)$q$, $q$índice plone27_cert_subject_idx$q$);
select pg_temp.ddl($q$CREATE UNIQUE INDEX IF NOT EXISTS plone27_disputes_subject_type_subject_id_idx ON public.plone27_disputes USING btree (subject_type, subject_id) WHERE (status = 'open'::text)$q$, $q$índice plone27_disputes_subject_type_subject_id_idx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS plone27_ledger_entries_account_id_idx ON public.plone27_ledger_entries USING btree (account_id)$q$, $q$índice plone27_ledger_entries_account_id_idx$q$);
select pg_temp.ddl($q$CREATE INDEX IF NOT EXISTS plone27_ledger_entries_transaction_id_idx ON public.plone27_ledger_entries USING btree (transaction_id)$q$, $q$índice plone27_ledger_entries_transaction_id_idx$q$);
-- ===== 7. VISTAS =====
select pg_temp.ddl($q$create or replace view public.plone27_account_balances with (security_invoker=true) as  SELECT a.id AS account_id,
    a.name,
    a.kind,
    a.status,
    COALESCE(sum(
        CASE
            WHEN (e.direction = 'credit'::text) THEN e.amount
            ELSE (- e.amount)
        END), (0)::numeric) AS booked,
    COALESCE(( SELECT sum(r.amount) AS sum
           FROM plone27_reservations r
          WHERE ((r.account_id = a.id) AND (r.status = 'active'::text))), (0)::numeric) AS reserved,
    a.bank_id
   FROM (plone27_accounts a
     LEFT JOIN plone27_ledger_entries e ON ((e.account_id = a.id)))
  GROUP BY a.id$q$, $q$vista plone27_account_balances$q$, $q$drop view if exists public.plone27_account_balances$q$);
select pg_temp.ddl($q$create or replace view public.plone27_alerts with (security_invoker=true) as  SELECT 'incidencias_abiertas'::text AS alerta,
    count(*) AS n
   FROM plone27_incidents
  WHERE (plone27_incidents.status = 'open'::text)
UNION ALL
 SELECT 'evaluaciones_en_revision'::text AS alerta,
    count(*) AS n
   FROM plone27_tax_evaluations
  WHERE (plone27_tax_evaluations.status = 'review'::text)
UNION ALL
 SELECT 'aprobaciones_pendientes'::text AS alerta,
    count(*) AS n
   FROM plone27_approvals
  WHERE (plone27_approvals.result IS NULL)
UNION ALL
 SELECT 'lotes_con_fallos'::text AS alerta,
    count(*) AS n
   FROM plone27_batch_items
  WHERE (plone27_batch_items.status = 'failed'::text)
UNION ALL
 SELECT 'webhooks_fallidos'::text AS alerta,
    count(*) AS n
   FROM plone27_outbox
  WHERE (plone27_outbox.status = 'failed'::text)
UNION ALL
 SELECT 'reembolsos_pendientes_de_fondos'::text AS alerta,
    count(*) AS n
   FROM plone27_justifications
  WHERE (plone27_justifications.status = 'approved'::text)
UNION ALL
 SELECT 'disputas_vencidas'::text AS alerta,
    count(*) AS n
   FROM plone27_disputes
  WHERE ((plone27_disputes.status = 'open'::text) AND (plone27_disputes.due_at < now()))$q$, $q$vista plone27_alerts$q$, $q$drop view if exists public.plone27_alerts$q$);
-- ===== 8. TRIGGERS =====
select pg_temp.ddl($q$drop trigger if exists t_account_compat on public.plone27_accounts$q$, $q$trigger (previo) t_account_compat$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_account_compat BEFORE INSERT OR UPDATE ON public.plone27_accounts FOR EACH ROW EXECUTE FUNCTION plone27_account_compat()$q$, $q$trigger t_account_compat en plone27_accounts$q$);
select pg_temp.ddl($q$drop trigger if exists t_iban on public.plone27_accounts$q$, $q$trigger (previo) t_iban$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_iban BEFORE INSERT OR UPDATE ON public.plone27_accounts FOR EACH ROW EXECUTE FUNCTION plone27_iban_guard()$q$, $q$trigger t_iban en plone27_accounts$q$);
select pg_temp.ddl($q$drop trigger if exists t_sub_create on public.plone27_accounts$q$, $q$trigger (previo) t_sub_create$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_sub_create AFTER UPDATE OF product_id ON public.plone27_accounts FOR EACH ROW EXECUTE FUNCTION plone27_sub_create()$q$, $q$trigger t_sub_create en plone27_accounts$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_approvals$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_approvals FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('AUT')$q$, $q$trigger t_ref en plone27_approvals$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref_lock on public.plone27_approvals$q$, $q$trigger (previo) t_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref_lock BEFORE UPDATE ON public.plone27_approvals FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_ref_lock en plone27_approvals$q$);
select pg_temp.ddl($q$drop trigger if exists t_audit_ro on public.plone27_audit_log$q$, $q$trigger (previo) t_audit_ro$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_audit_ro BEFORE DELETE OR UPDATE ON public.plone27_audit_log FOR EACH ROW EXECUTE FUNCTION plone27_immutable()$q$, $q$trigger t_audit_ro en plone27_audit_log$q$);
select pg_temp.ddl($q$drop trigger if exists t_emit on public.plone27_audit_log$q$, $q$trigger (previo) t_emit$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_emit AFTER INSERT ON public.plone27_audit_log FOR EACH ROW EXECUTE FUNCTION plone27_emit()$q$, $q$trigger t_emit en plone27_audit_log$q$);
select pg_temp.ddl($q$drop trigger if exists t_bank_accounts on public.plone27_banks$q$, $q$trigger (previo) t_bank_accounts$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_bank_accounts BEFORE INSERT OR UPDATE ON public.plone27_banks FOR EACH ROW EXECUTE FUNCTION plone27_bank_accounts_guard()$q$, $q$trigger t_bank_accounts en plone27_banks$q$);
select pg_temp.ddl($q$drop trigger if exists t_bank_guard on public.plone27_banks$q$, $q$trigger (previo) t_bank_guard$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_bank_guard BEFORE UPDATE ON public.plone27_banks FOR EACH ROW EXECUTE FUNCTION plone27_bank_guard()$q$, $q$trigger t_bank_guard en plone27_banks$q$);
select pg_temp.ddl($q$drop trigger if exists t_card_compat on public.plone27_cards$q$, $q$trigger (previo) t_card_compat$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_card_compat BEFORE INSERT ON public.plone27_cards FOR EACH ROW EXECUTE FUNCTION plone27_card_compat()$q$, $q$trigger t_card_compat en plone27_cards$q$);
select pg_temp.ddl($q$drop trigger if exists t_contract_guard on public.plone27_contracts$q$, $q$trigger (previo) t_contract_guard$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_contract_guard BEFORE INSERT OR UPDATE ON public.plone27_contracts FOR EACH ROW EXECUTE FUNCTION plone27_contract_guard()$q$, $q$trigger t_contract_guard en plone27_contracts$q$);
select pg_temp.ddl($q$drop trigger if exists t_debt_terms on public.plone27_debts$q$, $q$trigger (previo) t_debt_terms$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_debt_terms BEFORE INSERT OR UPDATE ON public.plone27_debts FOR EACH ROW EXECUTE FUNCTION plone27_debt_terms()$q$, $q$trigger t_debt_terms en plone27_debts$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_debts$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_debts FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('DEU')$q$, $q$trigger t_ref en plone27_debts$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref_lock on public.plone27_debts$q$, $q$trigger (previo) t_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref_lock BEFORE UPDATE ON public.plone27_debts FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_ref_lock en plone27_debts$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_disputes$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_disputes FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('DIS')$q$, $q$trigger t_ref en plone27_disputes$q$);
select pg_temp.ddl($q$drop trigger if exists t_fee_cap on public.plone27_fee_rules$q$, $q$trigger (previo) t_fee_cap$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_fee_cap BEFORE INSERT OR UPDATE ON public.plone27_fee_rules FOR EACH ROW EXECUTE FUNCTION plone27_fee_cap()$q$, $q$trigger t_fee_cap en plone27_fee_rules$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_grants$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_grants FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('SUB')$q$, $q$trigger t_ref en plone27_grants$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref_lock on public.plone27_grants$q$, $q$trigger (previo) t_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref_lock BEFORE UPDATE ON public.plone27_grants FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_ref_lock en plone27_grants$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_incidents$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_incidents FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('INC')$q$, $q$trigger t_ref en plone27_incidents$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref_lock on public.plone27_incidents$q$, $q$trigger (previo) t_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref_lock BEFORE UPDATE ON public.plone27_incidents FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_ref_lock en plone27_incidents$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_invoices$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_invoices FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('FAC')$q$, $q$trigger t_ref en plone27_invoices$q$);
select pg_temp.ddl($q$drop trigger if exists t_ids_ro on public.plone27_issued_ids$q$, $q$trigger (previo) t_ids_ro$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ids_ro BEFORE DELETE OR UPDATE ON public.plone27_issued_ids FOR EACH ROW EXECUTE FUNCTION plone27_immutable()$q$, $q$trigger t_ids_ro en plone27_issued_ids$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_justifications$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_justifications FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('JUS')$q$, $q$trigger t_ref en plone27_justifications$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref_lock on public.plone27_justifications$q$, $q$trigger (previo) t_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref_lock BEFORE UPDATE ON public.plone27_justifications FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_ref_lock en plone27_justifications$q$);
select pg_temp.ddl($q$drop trigger if exists t_reimb on public.plone27_justifications$q$, $q$trigger (previo) t_reimb$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_reimb BEFORE UPDATE ON public.plone27_justifications FOR EACH ROW EXECUTE FUNCTION plone27_reimb_ref()$q$, $q$trigger t_reimb en plone27_justifications$q$);
select pg_temp.ddl($q$drop trigger if exists t_credit_floor on public.plone27_ledger_entries$q$, $q$trigger (previo) t_credit_floor$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_credit_floor BEFORE INSERT ON public.plone27_ledger_entries FOR EACH ROW EXECUTE FUNCTION plone27_credit_floor()$q$, $q$trigger t_credit_floor en plone27_ledger_entries$q$);
select pg_temp.ddl($q$drop trigger if exists t_junior_cp on public.plone27_ledger_entries$q$, $q$trigger (previo) t_junior_cp$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_junior_cp AFTER INSERT ON public.plone27_ledger_entries REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION plone27_junior_counterparty()$q$, $q$trigger t_junior_cp en plone27_ledger_entries$q$);
select pg_temp.ddl($q$drop trigger if exists t_junior_profile on public.plone27_ledger_entries$q$, $q$trigger (previo) t_junior_profile$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_junior_profile BEFORE INSERT ON public.plone27_ledger_entries FOR EACH ROW EXECUTE FUNCTION plone27_junior_profile()$q$, $q$trigger t_junior_profile en plone27_ledger_entries$q$);
select pg_temp.ddl($q$drop trigger if exists t_ledger_ro on public.plone27_ledger_entries$q$, $q$trigger (previo) t_ledger_ro$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ledger_ro BEFORE DELETE OR UPDATE ON public.plone27_ledger_entries FOR EACH ROW EXECUTE FUNCTION plone27_immutable()$q$, $q$trigger t_ledger_ro en plone27_ledger_entries$q$);
select pg_temp.ddl($q$drop trigger if exists t_limits on public.plone27_ledger_entries$q$, $q$trigger (previo) t_limits$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_limits BEFORE INSERT ON public.plone27_ledger_entries FOR EACH ROW EXECUTE FUNCTION plone27_ledger_limits()$q$, $q$trigger t_limits en plone27_ledger_entries$q$);
select pg_temp.ddl($q$drop trigger if exists t_policy_guard on public.plone27_policies$q$, $q$trigger (previo) t_policy_guard$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_policy_guard BEFORE INSERT OR UPDATE ON public.plone27_policies FOR EACH ROW EXECUTE FUNCTION plone27_policy_guard()$q$, $q$trigger t_policy_guard en plone27_policies$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_policies$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_policies FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('POL')$q$, $q$trigger t_ref en plone27_policies$q$);
select pg_temp.ddl($q$drop trigger if exists t_product_guard on public.plone27_products$q$, $q$trigger (previo) t_product_guard$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_product_guard BEFORE UPDATE ON public.plone27_products FOR EACH ROW EXECUTE FUNCTION plone27_product_guard()$q$, $q$trigger t_product_guard en plone27_products$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_settlements$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_settlements FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('LIQ')$q$, $q$trigger t_ref en plone27_settlements$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_tax_adjustments$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_tax_adjustments FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('REG')$q$, $q$trigger t_ref en plone27_tax_adjustments$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref_lock on public.plone27_tax_adjustments$q$, $q$trigger (previo) t_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref_lock BEFORE UPDATE ON public.plone27_tax_adjustments FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_ref_lock en plone27_tax_adjustments$q$);
select pg_temp.ddl($q$drop trigger if exists t_bracket_guard on public.plone27_tax_brackets$q$, $q$trigger (previo) t_bracket_guard$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_bracket_guard BEFORE INSERT OR DELETE OR UPDATE ON public.plone27_tax_brackets FOR EACH ROW EXECUTE FUNCTION plone27_bracket_guard()$q$, $q$trigger t_bracket_guard en plone27_tax_brackets$q$);
select pg_temp.ddl($q$drop trigger if exists t_cert_ro on public.plone27_tax_certificates$q$, $q$trigger (previo) t_cert_ro$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_cert_ro BEFORE DELETE OR UPDATE ON public.plone27_tax_certificates FOR EACH ROW EXECUTE FUNCTION plone27_immutable()$q$, $q$trigger t_cert_ro en plone27_tax_certificates$q$);
select pg_temp.ddl($q$drop trigger if exists t_dist on public.plone27_tax_distribution$q$, $q$trigger (previo) t_dist$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_dist BEFORE INSERT OR UPDATE ON public.plone27_tax_distribution FOR EACH ROW EXECUTE FUNCTION plone27_dist_guard()$q$, $q$trigger t_dist en plone27_tax_distribution$q$);
select pg_temp.ddl($q$drop trigger if exists t_eval_ro on public.plone27_tax_evaluations$q$, $q$trigger (previo) t_eval_ro$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_eval_ro BEFORE DELETE OR UPDATE ON public.plone27_tax_evaluations FOR EACH ROW EXECUTE FUNCTION plone27_immutable()$q$, $q$trigger t_eval_ro en plone27_tax_evaluations$q$);
select pg_temp.ddl($q$drop trigger if exists t_cert_receipt on public.plone27_tax_receipts$q$, $q$trigger (previo) t_cert_receipt$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_cert_receipt AFTER INSERT ON public.plone27_tax_receipts FOR EACH ROW EXECUTE FUNCTION plone27_cert_receipt()$q$, $q$trigger t_cert_receipt en plone27_tax_receipts$q$);
select pg_temp.ddl($q$drop trigger if exists t_cert_receipt_upd on public.plone27_tax_receipts$q$, $q$trigger (previo) t_cert_receipt_upd$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_cert_receipt_upd AFTER UPDATE OF amount, base, rule_version_id ON public.plone27_tax_receipts FOR EACH ROW WHEN (((old.amount IS DISTINCT FROM new.amount) OR (old.base IS DISTINCT FROM new.base) OR (old.rule_version_id IS DISTINCT FROM new.rule_version_id))) EXECUTE FUNCTION plone27_cert_receipt_update()$q$, $q$trigger t_cert_receipt_upd en plone27_tax_receipts$q$);
select pg_temp.ddl($q$drop trigger if exists t_receipt_paid on public.plone27_tax_receipts$q$, $q$trigger (previo) t_receipt_paid$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_receipt_paid BEFORE UPDATE ON public.plone27_tax_receipts FOR EACH ROW EXECUTE FUNCTION plone27_receipt_paid()$q$, $q$trigger t_receipt_paid en plone27_tax_receipts$q$);
select pg_temp.ddl($q$drop trigger if exists t_receipt_routing on public.plone27_tax_receipts$q$, $q$trigger (previo) t_receipt_routing$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_receipt_routing BEFORE INSERT ON public.plone27_tax_receipts FOR EACH ROW EXECUTE FUNCTION plone27_receipt_routing()$q$, $q$trigger t_receipt_routing en plone27_tax_receipts$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref on public.plone27_tax_receipts$q$, $q$trigger (previo) t_ref$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref BEFORE INSERT ON public.plone27_tax_receipts FOR EACH ROW EXECUTE FUNCTION plone27_set_ref('REC')$q$, $q$trigger t_ref en plone27_tax_receipts$q$);
select pg_temp.ddl($q$drop trigger if exists t_ref_lock on public.plone27_tax_receipts$q$, $q$trigger (previo) t_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_ref_lock BEFORE UPDATE ON public.plone27_tax_receipts FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_ref_lock en plone27_tax_receipts$q$);
select pg_temp.ddl($q$drop trigger if exists t_rv_cap on public.plone27_tax_rule_versions$q$, $q$trigger (previo) t_rv_cap$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_rv_cap BEFORE INSERT OR UPDATE ON public.plone27_tax_rule_versions FOR EACH ROW EXECUTE FUNCTION plone27_rv_cap()$q$, $q$trigger t_rv_cap en plone27_tax_rule_versions$q$);
select pg_temp.ddl($q$drop trigger if exists t_rv_guard on public.plone27_tax_rule_versions$q$, $q$trigger (previo) t_rv_guard$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_rv_guard BEFORE UPDATE ON public.plone27_tax_rule_versions FOR EACH ROW EXECUTE FUNCTION plone27_rv_guard()$q$, $q$trigger t_rv_guard en plone27_tax_rule_versions$q$);
select pg_temp.ddl($q$drop trigger if exists t_on_reversed on public.plone27_transactions$q$, $q$trigger (previo) t_on_reversed$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_on_reversed BEFORE UPDATE ON public.plone27_transactions FOR EACH ROW EXECUTE FUNCTION plone27_on_reversed()$q$, $q$trigger t_on_reversed en plone27_transactions$q$);
select pg_temp.ddl($q$drop trigger if exists t_tx_nodel on public.plone27_transactions$q$, $q$trigger (previo) t_tx_nodel$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_tx_nodel BEFORE DELETE ON public.plone27_transactions FOR EACH ROW EXECUTE FUNCTION plone27_immutable()$q$, $q$trigger t_tx_nodel en plone27_transactions$q$);
select pg_temp.ddl($q$drop trigger if exists t_tx_ref_lock on public.plone27_transactions$q$, $q$trigger (previo) t_tx_ref_lock$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_tx_ref_lock BEFORE UPDATE ON public.plone27_transactions FOR EACH ROW EXECUTE FUNCTION plone27_ref_lock()$q$, $q$trigger t_tx_ref_lock en plone27_transactions$q$);
select pg_temp.ddl($q$drop trigger if exists t_tx_refs on public.plone27_transactions$q$, $q$trigger (previo) t_tx_refs$q$);
select pg_temp.ddl($q$CREATE TRIGGER t_tx_refs BEFORE INSERT ON public.plone27_transactions FOR EACH ROW EXECUTE FUNCTION plone27_tx_refs()$q$, $q$trigger t_tx_refs en plone27_transactions$q$);
-- ===== 9. SEGURIDAD: RLS, políticas y permisos =====
select pg_temp.ddl($q$alter table public.plone27_account_members enable row level security$q$, $q$RLS plone27_account_members$q$);
select pg_temp.ddl($q$alter table public.plone27_accounts enable row level security$q$, $q$RLS plone27_accounts$q$);
select pg_temp.ddl($q$alter table public.plone27_activities enable row level security$q$, $q$RLS plone27_activities$q$);
select pg_temp.ddl($q$alter table public.plone27_api_clients enable row level security$q$, $q$RLS plone27_api_clients$q$);
select pg_temp.ddl($q$alter table public.plone27_api_usage enable row level security$q$, $q$RLS plone27_api_usage$q$);
select pg_temp.ddl($q$alter table public.plone27_approvals enable row level security$q$, $q$RLS plone27_approvals$q$);
select pg_temp.ddl($q$alter table public.plone27_audit_log enable row level security$q$, $q$RLS plone27_audit_log$q$);
select pg_temp.ddl($q$alter table public.plone27_bank_settings enable row level security$q$, $q$RLS plone27_bank_settings$q$);
select pg_temp.ddl($q$alter table public.plone27_banks enable row level security$q$, $q$RLS plone27_banks$q$);
select pg_temp.ddl($q$alter table public.plone27_batch_items enable row level security$q$, $q$RLS plone27_batch_items$q$);
select pg_temp.ddl($q$alter table public.plone27_batches enable row level security$q$, $q$RLS plone27_batches$q$);
select pg_temp.ddl($q$alter table public.plone27_budgets enable row level security$q$, $q$RLS plone27_budgets$q$);
select pg_temp.ddl($q$alter table public.plone27_card_charges enable row level security$q$, $q$RLS plone27_card_charges$q$);
select pg_temp.ddl($q$alter table public.plone27_card_designs enable row level security$q$, $q$RLS plone27_card_designs$q$);
select pg_temp.ddl($q$alter table public.plone27_card_orders enable row level security$q$, $q$RLS plone27_card_orders$q$);
select pg_temp.ddl($q$alter table public.plone27_cards enable row level security$q$, $q$RLS plone27_cards$q$);
select pg_temp.ddl($q$alter table public.plone27_config enable row level security$q$, $q$RLS plone27_config$q$);
select pg_temp.ddl($q$alter table public.plone27_contracts enable row level security$q$, $q$RLS plone27_contracts$q$);
select pg_temp.ddl($q$alter table public.plone27_counters enable row level security$q$, $q$RLS plone27_counters$q$);
select pg_temp.ddl($q$alter table public.plone27_customers enable row level security$q$, $q$RLS plone27_customers$q$);
select pg_temp.ddl($q$alter table public.plone27_debts enable row level security$q$, $q$RLS plone27_debts$q$);
select pg_temp.ddl($q$alter table public.plone27_design_purchases enable row level security$q$, $q$RLS plone27_design_purchases$q$);
select pg_temp.ddl($q$alter table public.plone27_disputes enable row level security$q$, $q$RLS plone27_disputes$q$);
select pg_temp.ddl($q$alter table public.plone27_fee_rules enable row level security$q$, $q$RLS plone27_fee_rules$q$);
select pg_temp.ddl($q$alter table public.plone27_grant_programs enable row level security$q$, $q$RLS plone27_grant_programs$q$);
select pg_temp.ddl($q$alter table public.plone27_grants enable row level security$q$, $q$RLS plone27_grants$q$);
select pg_temp.ddl($q$alter table public.plone27_incidents enable row level security$q$, $q$RLS plone27_incidents$q$);
select pg_temp.ddl($q$alter table public.plone27_institutional_accounts enable row level security$q$, $q$RLS plone27_institutional_accounts$q$);
select pg_temp.ddl($q$alter table public.plone27_invoices enable row level security$q$, $q$RLS plone27_invoices$q$);
select pg_temp.ddl($q$alter table public.plone27_issued_ids enable row level security$q$, $q$RLS plone27_issued_ids$q$);
select pg_temp.ddl($q$alter table public.plone27_iva_findings enable row level security$q$, $q$RLS plone27_iva_findings$q$);
select pg_temp.ddl($q$alter table public.plone27_junior_profiles enable row level security$q$, $q$RLS plone27_junior_profiles$q$);
select pg_temp.ddl($q$alter table public.plone27_juniors enable row level security$q$, $q$RLS plone27_juniors$q$);
select pg_temp.ddl($q$alter table public.plone27_justifications enable row level security$q$, $q$RLS plone27_justifications$q$);
select pg_temp.ddl($q$alter table public.plone27_late_accruals enable row level security$q$, $q$RLS plone27_late_accruals$q$);
select pg_temp.ddl($q$alter table public.plone27_ledger_entries enable row level security$q$, $q$RLS plone27_ledger_entries$q$);
select pg_temp.ddl($q$alter table public.plone27_numbering_formats enable row level security$q$, $q$RLS plone27_numbering_formats$q$);
select pg_temp.ddl($q$alter table public.plone27_outbox enable row level security$q$, $q$RLS plone27_outbox$q$);
select pg_temp.ddl($q$alter table public.plone27_payslips enable row level security$q$, $q$RLS plone27_payslips$q$);
select pg_temp.ddl($q$alter table public.plone27_plan_items enable row level security$q$, $q$RLS plone27_plan_items$q$);
select pg_temp.ddl($q$alter table public.plone27_plans enable row level security$q$, $q$RLS plone27_plans$q$);
select pg_temp.ddl($q$alter table public.plone27_policies enable row level security$q$, $q$RLS plone27_policies$q$);
select pg_temp.ddl($q$alter table public.plone27_products enable row level security$q$, $q$RLS plone27_products$q$);
select pg_temp.ddl($q$alter table public.plone27_rbu_bonuses enable row level security$q$, $q$RLS plone27_rbu_bonuses$q$);
select pg_temp.ddl($q$alter table public.plone27_reservations enable row level security$q$, $q$RLS plone27_reservations$q$);
select pg_temp.ddl($q$alter table public.plone27_sales enable row level security$q$, $q$RLS plone27_sales$q$);
select pg_temp.ddl($q$alter table public.plone27_scheduled enable row level security$q$, $q$RLS plone27_scheduled$q$);
select pg_temp.ddl($q$alter table public.plone27_setting_changes enable row level security$q$, $q$RLS plone27_setting_changes$q$);
select pg_temp.ddl($q$alter table public.plone27_settings enable row level security$q$, $q$RLS plone27_settings$q$);
select pg_temp.ddl($q$alter table public.plone27_settlements enable row level security$q$, $q$RLS plone27_settlements$q$);
select pg_temp.ddl($q$alter table public.plone27_staff enable row level security$q$, $q$RLS plone27_staff$q$);
select pg_temp.ddl($q$alter table public.plone27_subscriptions enable row level security$q$, $q$RLS plone27_subscriptions$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_adjustments enable row level security$q$, $q$RLS plone27_tax_adjustments$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_brackets enable row level security$q$, $q$RLS plone27_tax_brackets$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_certificates enable row level security$q$, $q$RLS plone27_tax_certificates$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_distribution enable row level security$q$, $q$RLS plone27_tax_distribution$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_evaluations enable row level security$q$, $q$RLS plone27_tax_evaluations$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_exemptions enable row level security$q$, $q$RLS plone27_tax_exemptions$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_receipts enable row level security$q$, $q$RLS plone27_tax_receipts$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_rule_versions enable row level security$q$, $q$RLS plone27_tax_rule_versions$q$);
select pg_temp.ddl($q$alter table public.plone27_tax_rules enable row level security$q$, $q$RLS plone27_tax_rules$q$);
select pg_temp.ddl($q$alter table public.plone27_transactions enable row level security$q$, $q$RLS plone27_transactions$q$);
select pg_temp.ddl($q$alter table public.plone27_webhooks enable row level security$q$, $q$RLS plone27_webhooks$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_account_members$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_account_members as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_account_members$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_accounts$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_accounts as permissive for select to public using ((plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]) AND plone27_bank_visible(bank_id)))$q$, $q$política staff_read en plone27_accounts$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_activities$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_activities as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_activities$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_api_usage$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_api_usage as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_api_usage$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_approvals$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_approvals as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_approvals$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_audit_log$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_audit_log as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_audit_log$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_bank_settings$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_bank_settings as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_bank_settings$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_banks$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_banks as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_banks$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_batch_items$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_batch_items as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_batch_items$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_batches$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_batches as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_batches$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_budgets$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_budgets as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_budgets$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_card_charges$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_card_charges as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_card_charges$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_card_designs$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_card_designs as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_card_designs$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_card_orders$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_card_orders as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_card_orders$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_cards$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_cards as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_cards$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_config$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_config as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_config$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_contracts$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_contracts as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_contracts$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_counters$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_counters as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_counters$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_customers$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_customers as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_customers$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_debts$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_debts as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_debts$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_design_purchases$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_design_purchases as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_design_purchases$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_disputes$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_disputes as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_disputes$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_fee_rules$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_fee_rules as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_fee_rules$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_grant_programs$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_grant_programs as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_grant_programs$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_grants$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_grants as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_grants$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_incidents$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_incidents as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_incidents$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_institutional_accounts$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_institutional_accounts as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_institutional_accounts$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_invoices$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_invoices as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_invoices$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_issued_ids$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_issued_ids as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_issued_ids$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_iva_findings$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_iva_findings as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_iva_findings$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_junior_profiles$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_junior_profiles as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_junior_profiles$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_juniors$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_juniors as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_juniors$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_justifications$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_justifications as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_justifications$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_late_accruals$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_late_accruals as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_late_accruals$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_ledger_entries$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_ledger_entries as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_ledger_entries$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_numbering_formats$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_numbering_formats as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_numbering_formats$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_outbox$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_outbox as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_outbox$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_payslips$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_payslips as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_payslips$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_plan_items$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_plan_items as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_plan_items$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_plans$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_plans as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_plans$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_policies$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_policies as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_policies$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_products$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_products as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_products$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_rbu_bonuses$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_rbu_bonuses as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_rbu_bonuses$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_reservations$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_reservations as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_reservations$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_sales$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_sales as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_sales$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_scheduled$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_scheduled as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_scheduled$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_setting_changes$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_setting_changes as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_setting_changes$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_settings$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_settings as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_settings$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_settlements$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_settlements as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_settlements$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_staff$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_staff as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_staff$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_subscriptions$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_subscriptions as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_subscriptions$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_adjustments$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_adjustments as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_adjustments$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_brackets$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_brackets as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_brackets$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_certificates$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_certificates as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_certificates$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_distribution$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_distribution as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_distribution$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_evaluations$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_evaluations as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_evaluations$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_exemptions$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_exemptions as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_exemptions$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_receipts$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_receipts as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_receipts$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_rule_versions$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_rule_versions as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_rule_versions$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_tax_rules$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_tax_rules as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_tax_rules$q$);
select pg_temp.ddl($q$drop policy if exists staff_read on public.plone27_transactions$q$, $q$política (previa) staff_read$q$);
select pg_temp.ddl($q$create policy staff_read on public.plone27_transactions as permissive for select to public using (plone27_has_role(ARRAY['auditor'::text, 'financiero'::text, 'fiscal'::text, 'financiacion'::text, 'gestor_bancario'::text, 'aprobador'::text]))$q$, $q$política staff_read en plone27_transactions$q$);
do $g$ declare f text; begin
  for f in select p.oid::regprocedure::text from pg_proc p where p.pronamespace='public'::regnamespace and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
  begin
    execute 'grant usage on schema public to service_role';
    execute 'grant all on all tables in schema public to service_role'; execute 'grant all on all sequences in schema public to service_role';
  exception when others then insert into _p27_log(nivel,que,detalle) values('AVISO','permisos service_role',sqlerrm); end;
end $g$;
-- ===== 10. DATOS DE CATÁLOGO (solo inserta lo que falte; nunca modifica lo existente) =====
select pg_temp.ddl($q$INSERT INTO public.plone27_banks (id, code, name, active, description, status, valid_from, valid_to, approved_by, config, main_account, tax_account) VALUES ('bca551d4-b032-4552-8891-2b8d925a4330', '0000', 'Placeta Administración', true, NULL, 'active', NULL, NULL, NULL, '{}', NULL, NULL) ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_config (key, value) VALUES ('dual_approval_threshold', '1000') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('TAR', 1, 'PL27-TAR-', false, 8, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('TRF', 1, 'PL27-TRF-', false, 12, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('OPE', 1, 'PL27-OPE-', false, 12, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('AUT', 1, 'PL27-AUT-', false, 8, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('REC', 1, 'PL27-REC-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('LIQ', 1, 'PL27-LIQ-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('REG', 1, 'PL27-REG-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('SUB', 1, 'PL27-SUB-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('BON', 1, 'PL27-BON-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('JUS', 1, 'PL27-JUS-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('REE', 1, 'PL27-REE-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('FAC', 1, 'PL27-FAC-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('DEU', 1, 'PL27-DEU-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('INC', 1, 'PL27-INC-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('DIS', 1, 'PL27-DIS-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_numbering_formats (kind, version, prefix, year_scoped, width, status, reason, author, approved_by, valid_from) VALUES ('POL', 1, 'PL27-POL-', true, 6, 'published', 'inicial', NULL, NULL, '2026-10-29') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('dual_approval_threshold', 'aprobaciones', 'Importe (Pz) desde el que una regularización exige otra persona', 'number', NULL, 0, 1000000, '1000', true, false, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('unpaid_negative_adjustment_policy', 'fiscalidad', 'Regularización a favor del usuario sobre recibo sin pagar', 'enum', '{reject,credit_note,rectify}', NULL, NULL, '"reject"', true, true, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('default_receipt_due_days', 'fiscalidad', 'Días de vencimiento de recibos de ajuste', 'number', NULL, 1, 365, '30', false, true, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('late_penalty_enabled', 'fiscalidad', 'Permite recargos por mora (solo con norma autorizada)', 'boolean', NULL, NULL, NULL, 'false', true, false, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('late_penalty_rule_code', 'fiscalidad', 'Código de la norma fiscal que define el recargo', 'text', NULL, NULL, NULL, '""', true, false, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('default_daily_limit', 'cuentas', 'Límite diario por defecto en Pz (0 = sin límite)', 'number', NULL, 0, 100000000, '0', false, true, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('junior_default_limit', 'cuentas', 'Límite por operación Junior sin ficha (Pz)', 'number', NULL, 0, 100000, '20', false, true, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('webhook_max_attempts', 'integraciones', 'Reintentos de webhook antes de marcar fallo', 'number', NULL, 1, 20, '5', false, false, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('api_default_rate_limit', 'integraciones', 'Peticiones por minuto de un cliente API nuevo', 'number', NULL, 1, 10000, '60', false, true, 1, '2026-10-29 10:08:32.579286+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('penalty_max_pct', 'normas', 'Tope central (%) de un recargo por mora', 'number', NULL, 0, 100, '10', true, false, 1, '2026-10-29 10:08:32.69805+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('dispute_max_days', 'normas', 'Tope central de días para resolver una disputa', 'number', NULL, 1, 365, '90', true, false, 1, '2026-10-29 10:08:32.69805+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('debt_max_interest_pct', 'normas', 'Tope central del interés mensual (%) de una deuda', 'number', NULL, 0, 100, '5', true, false, 1, '2026-10-29 10:08:32.69805+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('junior_renewal_window_days', 'junior', 'Días antes del vencimiento en que se puede renovar la membresía', 'number', NULL, 0, 31, '5', false, true, 1, '2026-10-29 10:08:32.747524+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('junior_membership_grace_days', 'junior', 'Días de gracia tras vencer antes de pasar a «expirada»', 'number', NULL, 0, 60, '5', false, true, 1, '2026-10-29 10:08:32.747524+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('tasas_transferencia_max_pct', 'tasas', 'Tope (%) de la tasa de transferencia (Art. 4.3)', 'number', NULL, 0, 12, '12', true, false, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('interes_anual_pct', 'finanzas', 'Interés anual de cuotas y crédito (automático; cada entidad lo fija dentro del tope)', 'number', NULL, 0, 60, '0', true, true, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('demora_anual_pct', 'fiscalidad', 'Interés de demora anual (Art. 4.3; lo aprueba el Departamento Económico)', 'number', NULL, 0, 60, '0', true, false, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('periodo_gracia_mora_dias', 'fiscalidad', 'Días tras notificación o vencimiento antes de devengar mora', 'number', NULL, 0, 60, '7', true, false, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('autocobro_habilitado', 'cobros', 'Cobro automático en fecha de recibos, cuotas, suscripciones y deudas', 'boolean', NULL, NULL, NULL, 'true', true, true, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('rbu_semanal_pz', 'bienestar', 'Importe semanal de la RBU (Pz)', 'number', NULL, 0, 1000, '5', true, false, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('dia_nomina', 'laboral', 'Día del mes en que se paga la nómina (supuesto: confirmar)', 'number', NULL, 1, 28, '28', false, true, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('demora_habilitada', 'fiscalidad', 'Activa el interés de demora por segundo sobre recibos (Art. 4.3). Alternativa a los recargos escalonados del Art. T57', 'boolean', NULL, NULL, NULL, 'false', true, false, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('smi_mensual_completa_pz', 'laboral', 'SMI mensual para jornada completa (Pz). Instrucción de la Junta: 160 Pz al mes', 'number', NULL, 0, 100000, '160', true, false, 1, '2026-10-29 10:08:32.90026+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('iva_criterio', 'fiscalidad', 'Lectura del importe de una operación sin IVA desglosado: exclusivo = el importe es la base; inclusivo = el importe ya incluye el IVA', 'enum', '{exclusivo,inclusivo}', NULL, NULL, '"exclusivo"', true, false, 1, '2026-10-29 10:08:32.90026+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('iva_umbral_fraccionamiento', 'fiscalidad', 'Importe (Pz) a partir del cual varias transferencias pequeñas al mismo comercio en un día son fraccionamiento', 'number', NULL, 0, 1000000, '500', true, false, 1, '2026-10-29 10:08:32.90026+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('iva_patron_pagadores', 'fiscalidad', 'Nº de pagadores distintos a partir del cual una cuenta personal se revisa como posible comercio', 'number', NULL, 1, 1000, '5', true, false, 1, '2026-10-29 10:08:32.90026+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('iva_ventana_patron_dias', 'fiscalidad', 'Días de la ventana del patrón comercial en cuentas personales', 'number', NULL, 1, 365, '30', true, false, 1, '2026-10-29 10:08:32.90026+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('smi_semanal_completa_pz', 'laboral', 'Equivalente semanal informativo del SMI mensual (no valida contratos)', 'number', NULL, 0, 100000, '36.92', true, false, 1, '2026-10-29 10:08:32.79031+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
select pg_temp.ddl($q$INSERT INTO public.plone27_settings (key, category, description, vtype, allowed, min_v, max_v, value, sensitive, bank_overridable, version, updated_at) VALUES ('capitalia_asume_impuestos_junior', 'junior', 'Capitalia paga los impuestos de las operaciones Junior (si es false, paga Placeta Junior). Requiere publicar T105', 'boolean', NULL, NULL, NULL, 'true', true, false, 1, '2026-10-29 10:08:32.84906+01') ON CONFLICT DO NOTHING;$q$, $q$dato de catálogo$q$);
-- ===== 11. SEMILLAS NORMATIVAS (solo si faltan; entran en BORRADOR) =====
do $g$ begin if not exists(select 1 from plone27_tax_rules where code='IVA') then begin execute $sd$-- Placeta One · seed 0011 · Norma de tributos (Código Normativo | Tributos, Junta 26/09/2026)
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
$sd$; exception when others then insert into _p27_log(nivel,que,detalle) values('AVISO','semilla 0011_seed_norma_tributos_2027.sql',sqlerrm); end; end if; end $g$;
do $g$ begin if not exists(select 1 from plone27_tax_rules where code='RECARGO_T57') and exists(select 1 from plone27_tax_rules where code='IVA') then begin execute $sd$-- Placeta One · seed 0012 · Recargos T57 (Art. T57). Ejecutar después de 0011 y de su seed. Entra en BORRADOR.
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
$sd$; exception when others then insert into _p27_log(nivel,que,detalle) values('AVISO','semilla 0012_seed_normas_T.sql',sqlerrm); end; end if; end $g$;
do $g$ begin if not exists(select 1 from plone27_config where key='cuenta_tributos') and exists(select 1 from plone27_config where key='cuenta_reserva') then begin execute $sd$-- Placeta One · seed 0013 · Cuentas institucionales. Ejecutar después de 0012 y de los seeds 0011 y 0012.
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
$sd$; exception when others then insert into _p27_log(nivel,que,detalle) values('AVISO','semilla 0013_seed_cuentas_institucionales.sql',sqlerrm); end; end if; end $g$;
-- ===== 12. ADMINISTRADOR =====
do $g$ begin
  insert into plone27_staff(user_id,role,active) select u.id,'admin',true from auth.users u where lower(u.email)=lower('junta@laplaceta.org')
    on conflict (user_id) do update set role='admin', active=true;
  if not found then insert into _p27_log(nivel,que,detalle) values('AVISO','administrador','junta@laplaceta.org no existe aún en Authentication → Users: créalo y vuelve a ejecutar este script'); end if;
exception when others then insert into _p27_log(nivel,que,detalle) values('AVISO','administrador',sqlerrm); end $g$;
-- ===== 13. DIAGNÓSTICO: ejecuta cada consulta que hace el panel =====
do $g$ declare r record; ok int:=0; bad int:=0; begin
  for r in select * from (values
    ($q$panel · banks$q$,$q$select id,code,name,description,status,valid_from,valid_to from plone27_banks order by code limit 1$q$),
    ($q$panel · accounts$q$,$q$select id,iban,name,kind,status,daily_limit,bank_id,customer_id from plone27_accounts order by iban limit 1$q$),
    ($q$panel · clients$q$,$q$select id,name,scopes,rate_limit,active,bank_id,created_at from plone27_api_clients limit 1$q$),
    ($q$panel · webhooks$q$,$q$select id,url,events,active,bank_id from plone27_webhooks limit 1$q$),
    ($q$panel · fees$q$,$q$select id,op_type,method,rate,min_amount,max_amount,payer,valid_from,valid_to,bank_id from plone27_fee_rules limit 1$q$),
    ($q$panel · taxrules$q$,$q$select id,code,name,max_rate,collector_account from plone27_tax_rules order by code limit 1$q$),
    ($q$panel · taxversions$q$,$q$select id,rule_id,version,method,rate,min_amount,max_amount,valid_from,valid_to,status,retro_mode,reason,scope_op from plone27_tax_rule_versions order by version limit 1$q$),
    ($q$panel · products$q$,$q$select id,code,kind,name,status,daily_limit,monthly_fee,interest_rate,min_age,valid_from,valid_to,bank_id from plone27_products order by code limit 1$q$),
    ($q$panel · carddesigns$q$,$q$select id,name,tier,price,license_fee,status,revenue_account from plone27_card_designs limit 1$q$),
    ($q$panel · cards$q$,$q$select id,card_ref,account_id,kind,status,is_test,expires,last4,credit_limit from plone27_cards limit 1$q$),
    ($q$panel · transactions$q$,$q$select id,ref,transfer_ref,kind,status,memo,created_at from plone27_transactions order by created_at desc limit 1$q$),
    ($q$panel · scheduled$q$,$q$select id,from_account,to_account,amount,run_at,recurrence,status,memo from plone27_scheduled limit 1$q$),
    ($q$panel · batches$q$,$q$select id,kind,from_account,status from plone27_batches limit 1$q$),
    ($q$panel · batchitems$q$,$q$select id,batch_id,to_account,amount,status,error from plone27_batch_items limit 1$q$),
    ($q$panel · grantprograms$q$,$q$select id,name,kind,budget,funding_account from plone27_grant_programs limit 1$q$),
    ($q$panel · grants$q$,$q$select id,ref,program_id,beneficiary_account,granted,approved,paid from plone27_grants order by ref desc limit 1$q$),
    ($q$panel · justifications$q$,$q$select id,ref,grant_id,transaction_id,invoice_ref,amount,status,reimb_ref from plone27_justifications order by ref desc limit 1$q$),
    ($q$panel · budgets$q$,$q$select id,name,period,approved,committed,executed,restricted from plone27_budgets limit 1$q$),
    ($q$panel · debts$q$,$q$select id,ref,account_id,creditor_account,principal,authorized_charges,paid,due_date,disputed from plone27_debts order by ref desc limit 1$q$),
    ($q$panel · invoices$q$,$q$select id,ref,account_id,concept,amount,status from plone27_invoices order by ref desc limit 1$q$),
    ($q$panel · receipts$q$,$q$select id,ref,account_id,amount,paid_amount,status,due_date,disputed,created_at from plone27_tax_receipts order by created_at desc limit 1$q$),
    ($q$panel · exemptions$q$,$q$select id,rule_id,account_id,valid_from,valid_to,reason,legal_basis from plone27_tax_exemptions limit 1$q$),
    ($q$panel · distribution$q$,$q$select id,rule_id,account_id,pct from plone27_tax_distribution limit 1$q$),
    ($q$panel · settlements$q$,$q$select id,ref,bank_id,period_from,period_to,evaluated,collected,pending,refunded from plone27_settlements order by ref desc limit 1$q$),
    ($q$panel · incidents$q$,$q$select id,ref,kind,status,at,detail from plone27_incidents order by at desc limit 1$q$),
    ($q$panel · approvals$q$,$q$select id,ref,subject,subject_id,reason,result,at from plone27_approvals order by at desc limit 1$q$),
    ($q$panel · audit$q$,$q$select id,actor,action,entity,entity_id,at from plone27_audit_log order by id desc limit 1$q$),
    ($q$panel · numbering$q$,$q$select kind,version,prefix,year_scoped,width,status from plone27_numbering_formats order by kind limit 1$q$),
    ($q$panel · outbox$q$,$q$select id,event,status,attempts,created_at from plone27_outbox order by id desc limit 1$q$),
    ($q$panel · balances$q$,$q$select account_id,name,kind,status,booked,reserved,bank_id from plone27_account_balances order by name limit 1$q$),
    ($q$panel · ledger$q$,$q$select id,transaction_id,account_id,direction,amount,created_at from plone27_ledger_entries order by id desc limit 1$q$),
    ($q$panel · members$q$,$q$select account_id,user_id,role from plone27_account_members limit 1$q$),
    ($q$panel · juniors$q$,$q$select account_id,birth_date,guardian_user,per_tx_limit from plone27_juniors limit 1$q$),
    ($q$panel · brackets$q$,$q$select version_id,from_amount,to_amount,rate from plone27_tax_brackets order by from_amount limit 1$q$),
    ($q$panel · customers$q$,$q$select id,dip,full_name,bank_id,user_id,status from plone27_customers order by dip limit 1$q$),
    ($q$panel · policies$q$,$q$select id,ref,kind,name,scope,bank_id,customer_id,dip,params,valid_from,valid_to,status from plone27_policies order by created_at desc limit 1$q$),
    ($q$panel · disputes$q$,$q$select id,ref,subject_type,subject_id,reason,status,due_at,opened_at,resolution from plone27_disputes order by opened_at desc limit 1$q$),
    ($q$panel · juniorprofiles$q$,$q$select customer_id,birth_date,guardian_user,per_tx_limit,daily_limit,monthly_limit,card_enabled,locked from plone27_junior_profiles limit 1$q$),
    ($q$panel · subscriptions$q$,$q$select id,account_id,status,period_start,period_end,auto_renew,renewals from plone27_subscriptions order by period_end limit 1$q$),
    ($q$panel · staff$q$,$q$select user_id,role,active,bank_id from plone27_staff limit 1$q$),
    ($q$overview · alertas$q$,$q$select * from plone27_alerts$q$),
    ($q$overview · formatos$q$,$q$select kind,version,prefix,status from plone27_numbering_formats where status='published'$q$),
    ($q$ajustes$q$,$q$select * from plone27_settings order by category,key limit 1$q$),
    ($q$ajustes · cambios$q$,$q$select * from plone27_setting_changes where status='pending' order by at$q$),
    ($q$IVA · hallazgos$q$,$q$select * from plone27_iva_findings order by detected_at desc limit 1$q$),
    ($q$IVA · informe$q$,$q$select plone27_iva_report(current_date-30,current_date)$q$),
    ($q$estado · integridad$q$,$q$select * from plone27_integrity_report()$q$),
    ($q$estado · seguridad$q$,$q$select * from plone27_security_report()$q$),
    ($q$infraestructura · certificación$q$,$q$select plone27_certification_report()$q$),
    ($q$pasarela · certificación con p_actor$q$,$q$select plone27_certification_report(null::uuid)$q$),
    ($q$infraestructura · cuentas$q$,$q$select id,iban,name,kind,status,collectable from plone27_accounts limit 1$q$),
    ($q$infraestructura · bancos$q$,$q$select id,code,name,status,main_account,tax_account from plone27_banks limit 1$q$),
    ($q$infraestructura · institucionales$q$,$q$select account_id,motivo,puede_operar_junior,aprobado_por from plone27_institutional_accounts limit 1$q$),
    ($q$infraestructura · reglas$q$,$q$select id,code,name,collector_account,max_rate from plone27_tax_rules limit 1$q$),
    ($q$infraestructura · recibos$q$,$q$select status,amount,paid_amount from plone27_tax_receipts limit 1$q$),
    ($q$infraestructura · planes$q$,$q$select kind,status from plone27_plans limit 1$q$),
    ($q$infraestructura · cuotas$q$,$q$select status from plone27_plan_items limit 1$q$),
    ($q$infraestructura · RBU$q$,$q$select status,amount from plone27_rbu_bonuses limit 1$q$),
    ($q$infraestructura · contratos$q$,$q$select status,gross_monthly from plone27_contracts limit 1$q$),
    ($q$infraestructura · nóminas$q$,$q$select net from plone27_payslips limit 1$q$),
    ($q$infraestructura · ventas$q$,$q$select base,iva,origin from plone27_sales limit 1$q$),
    ($q$personal$q$,$q$select user_id,role,active,bank_id from plone27_staff limit 1$q$)
  ) as v(n,s) loop
    begin execute r.s; ok:=ok+1; exception when others then bad:=bad+1; insert into _p27_log(nivel,que,detalle) values('ERROR','consulta del panel: '||r.n,sqlerrm); end;
  end loop;
  insert into _p27_log(nivel,que,detalle) values(case when bad=0 then 'OK' else 'RESUMEN' end,'diagnóstico', ok||' consultas del panel correctas, '||bad||' con error');
end $g$;
analyze;
select nivel as "Nivel", que as "Qué", detalle as "Detalle" from _p27_log order by (nivel='OK'), n;
