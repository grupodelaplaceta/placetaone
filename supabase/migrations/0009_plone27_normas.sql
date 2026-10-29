-- Clientes (DIP) y normas configurables: recargos, disputas y condiciones de deuda. Ámbito: global < banco < cliente = DIP. Topes centrales no superables.
create table plone27_customers(id uuid primary key default gen_random_uuid(), dip text unique not null check(dip ~ '^[A-Z0-9-]{4,24}$'), full_name text not null, bank_id uuid references plone27_banks,
 user_id uuid, status text not null default 'active' check(status in('active','blocked')), created_at timestamptz default now());
alter table plone27_accounts add column customer_id uuid references plone27_customers;
create table plone27_policies(id uuid primary key default gen_random_uuid(), ref text unique, kind text not null check(kind in('penalty','dispute','debt_terms')), name text not null,
 scope text not null check(scope in('global','bank','customer','dip')), bank_id uuid references plone27_banks, customer_id uuid references plone27_customers, dip text, params jsonb not null default '{}',
 valid_from date not null default current_date, valid_to date, status text not null default 'draft' check(status in('draft','published','retired')), reason text, approved_by uuid, created_by uuid, created_at timestamptz default now());
insert into plone27_settings(key,category,description,vtype,min_v,max_v,value,sensitive,bank_overridable) values
('penalty_max_pct','normas','Tope central (%) de un recargo por mora','number',0,100,'10',true,false),
('dispute_max_days','normas','Tope central de días para resolver una disputa','number',1,365,'90',true,false),
('debt_max_interest_pct','normas','Tope central del interés mensual (%) de una deuda','number',0,100,'5',true,false);
insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,status,reason) values('DIS',1,'PL27-DIS-',true,6,'published','inicial'),('POL',1,'PL27-POL-',true,6,'published','inicial');
create trigger t_ref before insert on plone27_policies for each row execute function plone27_set_ref('POL');
create function plone27_policy_guard() returns trigger language plpgsql as $$ declare p jsonb:=new.params; begin
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
create trigger t_policy_guard before insert or update on plone27_policies for each row execute function plone27_policy_guard();
-- Resolución: la más específica gana; empate en el mismo nivel = incidencia y sin aplicar (nunca se elige al azar)
create function plone27_policy_resolve(p_kind text,p_account uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare a plone27_accounts; v_dip text; ids uuid[]; r jsonb; begin
 select * into a from plone27_accounts where id=p_account; select c.dip into v_dip from plone27_customers c where c.id=a.customer_id;
 with c as(select p.id,case p.scope when 'global' then 1 when 'bank' then 2 else 3 end lvl from plone27_policies p where p.kind=p_kind and p.status='published' and current_date>=p.valid_from and (p.valid_to is null or current_date<=p.valid_to)
  and (p.scope='global' or (p.scope='bank' and p.bank_id=a.bank_id) or (p.scope='customer' and p.customer_id=a.customer_id) or (p.scope='dip' and p.dip=v_dip)))
 select array_agg(c.id) into ids from c where c.lvl=(select max(lvl) from c);
 if ids is null then return null; end if;
 if array_length(ids,1)>1 then insert into plone27_incidents(kind,detail) values('policy_conflict',jsonb_build_object('kind',p_kind,'account',p_account,'policies',ids)); return null; end if;
 select p.params||jsonb_build_object('policy',p.id,'approved_by',p.approved_by) into r from plone27_policies p where p.id=ids[1]; return r; end $$;
-- Deuda: condiciones aplicadas por norma
alter table plone27_debts add column origin text unique;
create function plone27_debt_terms() returns trigger language plpgsql security definer set search_path=public as $$ declare pol jsonb; begin
 if new.account_id is null then return new; end if; pol:=plone27_policy_resolve('debt_terms',new.account_id); if pol is null then return new; end if;
 if tg_op='INSERT' and pol->>'max_principal' is not null and new.principal>(pol->>'max_principal')::numeric then raise exception 'Supera el principal máximo de la norma (%)',pol->>'max_principal'; end if;
 if tg_op='UPDATE' and new.paid>old.paid and pol->>'allow_partial'='false' and new.paid<new.principal+new.authorized_charges then raise exception 'La norma no permite pagos parciales'; end if; return new; end $$;
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
create table plone27_disputes(id uuid primary key default gen_random_uuid(), ref text unique, subject_type text not null check(subject_type in('receipt','debt')), subject_id uuid not null, account_id uuid references plone27_accounts,
 reason text not null, status text not null default 'open' check(status in('open','upheld','rejected','withdrawn')), opened_by uuid, opened_at timestamptz default now(), due_at timestamptz, resolution text, resolved_by uuid, resolved_at timestamptz);
create unique index on plone27_disputes(subject_type,subject_id) where status='open';
create trigger t_ref before insert on plone27_disputes for each row execute function plone27_set_ref('DIS');
create function plone27_dispute_open(p_type text,p_subject uuid,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$ declare acc uuid; pol jsonb; did uuid; begin
 if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 if p_type='receipt' then select account_id into acc from plone27_tax_receipts where id=p_subject; else select account_id into acc from plone27_debts where id=p_subject; end if;
 if acc is null then raise exception 'Objeto inexistente'; end if;
 pol:=plone27_policy_resolve('dispute',acc);
 insert into plone27_disputes(subject_type,subject_id,account_id,reason,opened_by,due_at) values(p_type,p_subject,acc,p_reason,p_actor,now()+make_interval(days=>coalesce((pol->>'max_days')::int,30))) returning plone27_disputes.id into did;
 if p_type='receipt' then update plone27_tax_receipts set disputed=true where id=p_subject; else update plone27_debts set disputed=true where id=p_subject; end if; return did; end $$;
create function plone27_dispute_resolve(p_id uuid,p_outcome text,p_note text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare d plone27_disputes; begin
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
