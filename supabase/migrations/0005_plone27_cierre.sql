-- Alcance por entidad para el personal
alter table plone27_staff add column bank_id uuid references plone27_banks;   -- null = global
create function plone27_bank_visible(p_bank uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from plone27_staff s where s.user_id=auth.uid() and s.active and (s.bank_id is null or s.bank_id=p_bank)) $$;
drop policy staff_read on plone27_accounts;
create policy staff_read on plone27_accounts for select using (plone27_has_role(array['auditor','financiero','fiscal','financiacion','gestor_bancario','aprobador']) and plone27_bank_visible(bank_id));
create or replace view plone27_account_balances with(security_invoker=true) as
select a.id account_id, a.name, a.kind, a.status,
  coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) booked,
  coalesce((select sum(r.amount) from plone27_reservations r where r.account_id=a.id and r.status='active'),0) reserved, a.bank_id
from plone27_accounts a left join plone27_ledger_entries e on e.account_id=a.id group by a.id;

-- Doble aprobación (umbral configurable) y solicitudes de aprobación genéricas
create table plone27_config(key text primary key, value text not null);
insert into plone27_config values('dual_approval_threshold','1000');
create or replace function plone27_adjust_approve(p_adj uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$
declare a plone27_tax_adjustments; begin
 select * into a from plone27_tax_adjustments where id=p_adj for update;
 if a.created_by is not distinct from p_actor and abs(a.diff)>=(select value::numeric from plone27_config where key='dual_approval_threshold') then raise exception 'Doble aprobación: debe aprobar otra persona'; end if;
 update plone27_tax_adjustments set status='approved',approved_by=p_actor where id=p_adj and status='simulated'; end $$;
create function plone27_approval_request(p_subject text,p_subject_id uuid,p_reason text,p_actor uuid) returns uuid language sql security definer set search_path=public as
$$ insert into plone27_approvals(subject,subject_id,requested_by,reason) values(p_subject,p_subject_id,p_actor,p_reason) returning id $$;
create function plone27_approval_decide(p_id uuid,p_approve boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 if exists(select 1 from plone27_approvals where id=p_id and requested_by is not distinct from p_actor) then raise exception 'El solicitante no puede aprobar su propia solicitud'; end if;
 update plone27_approvals set approved_by=p_actor,result=case when p_approve then 'approved' else 'rejected' end where id=p_id and result is null; end $$;

-- Tramos fiscales y pagos parciales
alter table plone27_tax_rule_versions drop constraint plone27_tax_rule_versions_method_check, add check(method in('percent','fixed','brackets'));
create table plone27_tax_brackets(version_id uuid not null references plone27_tax_rule_versions, from_amount numeric(18,2) not null, to_amount numeric(18,2), rate numeric(9,4) not null, primary key(version_id,from_amount));
create or replace function plone27_tax_calc(p_version uuid,p_base numeric) returns numeric language sql stable as $$
 select round(least(coalesce(v.max_amount,'infinity'),greatest(coalesce(v.min_amount,0),
  case v.method when 'percent' then p_base*v.rate/100 when 'fixed' then v.rate
   else coalesce((select sum((least(p_base,coalesce(b.to_amount,'infinity'))-b.from_amount)*b.rate/100) from plone27_tax_brackets b where b.version_id=v.id and p_base>b.from_amount),0) end)),2)
 from plone27_tax_rule_versions v where v.id=p_version $$;
alter table plone27_tax_receipts drop constraint plone27_tax_receipts_status_check, add check(status in('issued','partial','paid','rectified')), add column paid_amount numeric(18,2) not null default 0;
create function plone27_tax_pay_partial(p_key text,p_receipt uuid,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
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
create table plone27_webhooks(id uuid primary key default gen_random_uuid(), bank_id uuid not null references plone27_banks, url text not null check(url ~ '^https://'), secret text not null, events text[] not null default '{*}', active boolean not null default true);
create table plone27_outbox(id bigint generated always as identity primary key, event text not null, bank_ids uuid[] not null default '{}', payload jsonb, status text not null default 'pending' check(status in('pending','sent','failed')), attempts int not null default 0, created_at timestamptz default now());
create function plone27_emit() returns trigger language plpgsql security definer set search_path=public as $$ declare b uuid[]; p jsonb; begin
 if new.action='post' then
  select array_agg(distinct a.bank_id) into b from plone27_accounts a where a.id in(select (x->>'account')::uuid from jsonb_array_elements(new.detail) x);
  select jsonb_build_object('operation',t.ref,'transfer',t.transfer_ref,'kind',t.kind) into p from plone27_transactions t where t.id=new.entity_id::uuid;
  insert into plone27_outbox(event,bank_ids,payload) values('transaction.posted',coalesce(b,'{}'),p); end if; return new; end $$;
create trigger t_emit after insert on plone27_audit_log for each row execute function plone27_emit();
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
