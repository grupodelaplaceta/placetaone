-- Placeta One v1.1 · bancos, tarifas, vías fiscales, tarjetas, financiación. Solo Pz.
-- BANCOS: ciclo de vida
alter table plone27_banks add column description text, add column status text not null default 'draft' check(status in('draft','review','active','suspended','closed')),
 add column valid_from date, add column valid_to date, add column approved_by uuid, add column config jsonb not null default '{}';
create function plone27_bank_guard() returns trigger language plpgsql as $$ begin
 if new.status is distinct from old.status then
  if (old.status,new.status) not in(('draft','review'),('review','draft'),('review','active'),('active','suspended'),('suspended','active'),('active','closed'),('suspended','closed'))
   then raise exception 'Transición % → % no permitida',old.status,new.status; end if;
  if new.status='active' and new.approved_by is null then raise exception 'Activar requiere aprobación registrada'; end if; end if; return new; end $$;
create trigger t_bank_guard before update on plone27_banks for each row execute function plone27_bank_guard();
create table plone27_incidents(id uuid primary key default gen_random_uuid(), kind text, detail jsonb, status text default 'open', at timestamptz default now());

-- TARIFAS (distintas de impuestos)
create table plone27_fee_rules(id uuid primary key default gen_random_uuid(), bank_id uuid references plone27_banks, op_type text not null default 'transfer',
 method text not null check(method in('percent','fixed')), rate numeric(9,4) not null, min_amount numeric(18,2), max_amount numeric(18,2),
 payer text not null check(payer in('user','bank','both','exempt')), bank_pay_account uuid references plone27_accounts,
 beneficiary_account uuid not null references plone27_accounts, valid_from date not null, valid_to date, approved_by uuid);
create function plone27_transfer_fee(p_key text,p_from uuid,p_to uuid,p_amount numeric,p_memo text,p_actor uuid) returns uuid
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
alter table plone27_tax_rules add column max_rate numeric(9,4), add column collector_account uuid references plone27_accounts;
alter table plone27_tax_rule_versions add column scope_bank uuid references plone27_banks, add column scope_op text,
 add column retro_mode text not null default 'prohibited' check(retro_mode in('prohibited','simulation','automatic'));
create function plone27_rv_cap() returns trigger language plpgsql as $$ declare m numeric; begin
 select max_rate into m from plone27_tax_rules where id=new.rule_id;
 if (new.scope_bank is not null or new.scope_op is not null) and m is not null and new.method='percent' and new.rate>m then raise exception 'Regla específica supera el límite central (%)',m; end if; return new; end $$;
create trigger t_rv_cap before insert or update on plone27_tax_rule_versions for each row execute function plone27_rv_cap();
create table plone27_tax_exemptions(id uuid primary key default gen_random_uuid(), rule_id uuid references plone27_tax_rules, account_id uuid references plone27_accounts,
 valid_from date not null, valid_to date, reason text not null, legal_basis text not null, approved_by uuid not null);
create table plone27_tax_distribution(id uuid primary key default gen_random_uuid(), rule_id uuid not null references plone27_tax_rules, account_id uuid not null references plone27_accounts,
 pct numeric(5,2) not null check(pct>0 and pct<=100), approved_by uuid);
create function plone27_dist_guard() returns trigger language plpgsql as $$ begin
 if (select coalesce(sum(pct),0) from plone27_tax_distribution where rule_id=new.rule_id and id<>new.id)+new.pct>100 then raise exception 'La distribución supera el 100%%'; end if; return new; end $$;
create trigger t_dist before insert or update on plone27_tax_distribution for each row execute function plone27_dist_guard();
create table plone27_tax_evaluations(id uuid primary key default gen_random_uuid(), event_key text unique not null, rule_id uuid references plone27_tax_rules,
 rule_version_id uuid references plone27_tax_rule_versions, account_id uuid references plone27_accounts,
 pathway text not null check(pathway in('automatica','periodica','recibo','declaracion','regularizacion','liquidacion_bancaria','devolucion','revision_manual')),
 base numeric(18,2), amount numeric(18,2), status text not null default 'calculated' check(status in('calculated','review','exempt')), created_at timestamptz default now());
alter table plone27_tax_receipts add column evaluation_id uuid references plone27_tax_evaluations, add column paid_tx uuid references plone27_transactions, add column refunded numeric(18,2) not null default 0;

create function plone27_tax_issue(p_code text,p_account uuid,p_base numeric,p_event_key text,p_op text,p_pathway text,p_due date,p_actor uuid) returns uuid
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

create function plone27_tax_pay(p_key text,p_receipt uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare r record; dl jsonb; ds numeric; lines jsonb; tx uuid; begin
 select t.*,ru.collector_account col,ru.id rule into r from plone27_tax_receipts t join plone27_tax_rule_versions v on v.id=t.rule_version_id join plone27_tax_rules ru on ru.id=v.rule_id where t.id=p_receipt for update of t;
 if r.status='paid' then return r.paid_tx; end if; if r.status<>'issued' then raise exception 'Recibo no cobrable'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('account',account_id,'dir','credit','amount',round(r.amount*pct/100,2))),'[]'),coalesce(sum(round(r.amount*pct/100,2)),0) into dl,ds from plone27_tax_distribution where rule_id=r.rule;
 lines:=jsonb_build_array(jsonb_build_object('account',r.account_id,'dir','debit','amount',r.amount))||dl;
 if r.amount-ds>0 then lines:=lines||jsonb_build_object('account',r.col,'dir','credit','amount',r.amount-ds); end if;
 tx:=plone27_post(p_key,'tax_payment',null,lines,p_actor);
 update plone27_tax_receipts set status='paid',paid_tx=tx where id=p_receipt; return tx; end $$;  -- 'pagado' solo tras contabilizar

-- REGULARIZACIONES RETROACTIVAS
create table plone27_tax_adjustments(id uuid primary key default gen_random_uuid(), receipt_id uuid not null references plone27_tax_receipts, new_version_id uuid not null references plone27_tax_rule_versions,
 original_amount numeric(18,2), corrected_amount numeric(18,2), diff numeric(18,2), status text default 'simulated' check(status in('simulated','approved','executed')),
 created_by uuid, approved_by uuid, adj_receipt uuid, adj_tx uuid, unique(receipt_id,new_version_id));
create function plone27_adjust_simulate(p_receipt uuid,p_version uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare r plone27_tax_receipts; v plone27_tax_rule_versions; c numeric; aid uuid; begin
 select * into r from plone27_tax_receipts where id=p_receipt; select * into v from plone27_tax_rule_versions where id=p_version and status='published';
 if v.id is null or v.retro_mode='prohibited' then raise exception 'La regla no permite retroactividad'; end if;
 if r.created_at::date<v.valid_from or (v.valid_to is not null and r.created_at::date>v.valid_to) then raise exception 'Recibo fuera del ámbito de vigencia'; end if;
 c:=plone27_tax_calc(p_version,r.base);
 insert into plone27_tax_adjustments(receipt_id,new_version_id,original_amount,corrected_amount,diff,created_by) values(p_receipt,p_version,r.amount,c,c-r.amount,p_actor) returning plone27_tax_adjustments.id into aid; return aid; end $$;
create function plone27_adjust_approve(p_adj uuid,p_actor uuid) returns void language sql security definer set search_path=public as
$$ update plone27_tax_adjustments set status='approved',approved_by=p_actor where id=p_adj and status='simulated' $$;
create function plone27_adjust_execute(p_adj uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
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
create table plone27_card_designs(id uuid primary key default gen_random_uuid(), name text not null, tier text not null check(tier in('free','premium','commissioned','limited')),
 price numeric(18,2) not null default 0, license_fee numeric(18,2) not null default 0, revenue_account uuid references plone27_accounts, owner uuid,
 status text not null default 'draft' check(status in('draft','submitted','review','approved','rejected')), elements jsonb not null default '{}',
 check(not (elements ?| array['pan','cvv','chip','banda','antena','stripe','antenna','limit','status','balance'])));  -- el diseño no toca datos de seguridad ni permisos
create table plone27_design_purchases(design_id uuid references plone27_card_designs, account_id uuid references plone27_accounts, tx uuid, primary key(design_id,account_id));
create table plone27_cards(id uuid primary key default gen_random_uuid(), account_id uuid not null references plone27_accounts, kind text not null check(kind in('digital','physical','credit')),
 status text not null default 'active' check(status in('active','blocked','closed')), design_id uuid references plone27_card_designs, credit_limit numeric(18,2));
create table plone27_card_charges(id uuid primary key default gen_random_uuid(), card_id uuid not null references plone27_cards, merchant_account uuid not null references plone27_accounts,
 amount numeric(18,2) not null check(amount>0), status text not null default 'authorized' check(status in('authorized','billed','settled','released')), reservation_id uuid references plone27_reservations, at timestamptz default now());
create function plone27_design_step(p_design uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare o text; begin
 select status into o from plone27_card_designs where id=p_design for update;
 if (o,p_to) not in(('draft','submitted'),('submitted','review'),('review','approved'),('review','rejected'),('rejected','draft')) then raise exception 'Transición no permitida'; end if;
 update plone27_card_designs set status=p_to where id=p_design; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'design_step','design',p_design::text,to_jsonb(p_to)); end $$;
create function plone27_design_buy(p_key text,p_design uuid,p_account uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare d plone27_card_designs; tx uuid; t numeric; begin
 select * into d from plone27_card_designs where id=p_design; if d.status<>'approved' then raise exception 'Diseño no aprobado'; end if;
 t:=d.price+d.license_fee; if t>0 then tx:=plone27_transfer(p_key,p_account,d.revenue_account,t,'Diseño '||d.name,p_actor); end if;
 insert into plone27_design_purchases values(p_design,p_account,tx) on conflict do nothing; return tx; end $$;
create function plone27_card_authorize(p_card uuid,p_amount numeric,p_merchant uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare c plone27_cards; res uuid; ch uuid; begin
 select * into c from plone27_cards where id=p_card for update; if c.status<>'active' then raise exception 'Tarjeta no activa'; end if;
 if c.kind='credit' then
  if coalesce((select sum(amount) from plone27_card_charges where card_id=p_card and status in('authorized','billed')),0)+p_amount>coalesce(c.credit_limit,0) then raise exception 'Límite de crédito superado'; end if;
 else if plone27_available(c.account_id)<p_amount then raise exception 'Saldo insuficiente'; end if;
  insert into plone27_reservations(account_id,amount,reason) values(c.account_id,p_amount,'card auth') returning id into res; end if;
 insert into plone27_card_charges(card_id,merchant_account,amount,reservation_id) values(p_card,p_merchant,p_amount,res) returning id into ch; return ch; end $$;
create function plone27_card_settle(p_key text,p_charge uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare ch plone27_card_charges; c plone27_cards; tx uuid; begin
 select * into ch from plone27_card_charges where id=p_charge for update; if ch.status<>'authorized' then raise exception 'Cargo ya procesado'; end if;
 select * into c from plone27_cards where id=ch.card_id;
 if c.kind='credit' then update plone27_card_charges set status='billed' where id=p_charge; return null; end if;  -- crédito: consumo ≠ liquidación
 update plone27_reservations set status='released' where id=ch.reservation_id;
 tx:=plone27_transfer(p_key,c.account_id,ch.merchant_account,ch.amount,'Tarjeta',p_actor); update plone27_card_charges set status='settled' where id=p_charge; return tx; end $$;
create function plone27_card_close_cycle(p_key text,p_card uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare c plone27_cards; lines jsonb; tot numeric; begin
 select * into c from plone27_cards where id=p_card for update;
 select sum(amount) into tot from plone27_card_charges where card_id=p_card and status='billed'; if coalesce(tot,0)=0 then return null; end if;
 select jsonb_build_array(jsonb_build_object('account',c.account_id,'dir','debit','amount',tot))||jsonb_agg(jsonb_build_object('account',m,'dir','credit','amount',s)) into lines
  from(select merchant_account m,sum(amount) s from plone27_card_charges where card_id=p_card and status='billed' group by 1)q;
 update plone27_card_charges set status='settled' where card_id=p_card and status='billed';
 return plone27_post(p_key,'credit_cycle',null,lines,p_actor); end $$;

-- PROGRAMADAS
create table plone27_scheduled(id uuid primary key default gen_random_uuid(), from_account uuid references plone27_accounts, to_account uuid references plone27_accounts,
 amount numeric(18,2) not null check(amount>0), run_at timestamptz not null, recurrence interval, status text default 'active' check(status in('active','done','cancelled')), memo text);
create function plone27_run_scheduled(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare s record; n int:=0; begin
 for s in select * from plone27_scheduled where status='active' and run_at<=now() order by run_at for update skip locked loop
  begin perform plone27_transfer_fee('sch:'||s.id||':'||s.run_at,s.from_account,s.to_account,s.amount,s.memo,p_actor); n:=n+1;
   if s.recurrence is null then update plone27_scheduled set status='done' where id=s.id; else update plone27_scheduled set run_at=run_at+recurrence where id=s.id; end if;
  exception when others then insert into plone27_incidents(kind,detail) values('scheduled_failed',jsonb_build_object('id',s.id,'err',sqlerrm)); end;
 end loop; return n; end $$;

-- SUBVENCIONES Y BONOS
alter table plone27_grant_programs add column funding_account uuid references plone27_accounts;
alter table plone27_justifications drop constraint plone27_justifications_status_check, add check(status in('pending','approved','paid','rejected'));
create function plone27_justify(p_grant uuid,p_tx uuid,p_invoice text,p_amount numeric,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare g plone27_grants; spent numeric; jid uuid; begin
 select * into g from plone27_grants where id=p_grant for update;
 select sum(e.amount) into spent from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id where e.transaction_id=p_tx and e.account_id=g.beneficiary_account and e.direction='debit' and t.status='posted';
 if coalesce(spent,0)<p_amount then raise exception 'Transacción no elegible o importe excesivo'; end if;
 if coalesce((select sum(amount) from plone27_justifications where grant_id=p_grant and status<>'rejected'),0)+p_amount>g.granted then raise exception 'Supera lo concedido'; end if;
 insert into plone27_justifications(grant_id,transaction_id,invoice_ref,amount) values(p_grant,p_tx,p_invoice,p_amount) returning plone27_justifications.id into jid; return jid; end $$;  -- unique(transaction_id/invoice) impide justificar dos veces
create function plone27_reimburse(p_key text,p_just uuid,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare j plone27_justifications; g plone27_grants; f uuid; tx uuid; begin
 select * into j from plone27_justifications where id=p_just for update; if j.status not in('pending','approved') then raise exception 'Ya pagada o rechazada'; end if;
 select * into g from plone27_grants where id=j.grant_id for update; select funding_account into f from plone27_grant_programs where id=g.program_id;
 if j.status='pending' then update plone27_grants set approved=approved+j.amount where id=g.id; update plone27_justifications set status='approved' where id=p_just; end if;
 if plone27_available(f)<j.amount then return null; end if;   -- sin fondos: queda aprobado/pendiente, nunca "pagado"
 tx:=plone27_transfer(p_key,f,g.beneficiary_account,j.amount,'Reembolso',p_actor);
 update plone27_grants set paid=paid+j.amount where id=g.id; update plone27_justifications set status='paid' where id=p_just; return tx; end $$;

-- TESORERÍA
create table plone27_debts(id uuid primary key default gen_random_uuid(), account_id uuid references plone27_accounts, principal numeric(18,2) not null, authorized_charges numeric(18,2) default 0,
 paid numeric(18,2) default 0, due_date date, disputed boolean default false, authorized_by uuid not null, reason text not null);

do $$ declare t text; begin for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%'
 and not exists(select 1 from pg_policies p where p.tablename=pg_tables.tablename and p.policyname='staff_read') loop
 execute format('alter table %I enable row level security',t);
 execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end loop; end $$;
grant execute on function plone27_transfer_fee,plone27_tax_issue,plone27_tax_pay,plone27_adjust_simulate,plone27_adjust_approve,plone27_adjust_execute,plone27_design_step,plone27_design_buy,
 plone27_card_authorize,plone27_card_settle,plone27_card_close_cycle,plone27_run_scheduled,plone27_justify,plone27_reimburse,plone27_reverse to service_role;
