-- Configuración central: global + sobrescritura por entidad dentro de límites centrales; historial y aprobación de cambios sensibles
create table plone27_settings(key text primary key, category text not null, description text not null, vtype text not null check(vtype in('number','boolean','text','enum')),
 allowed text[], min_v numeric, max_v numeric, value jsonb not null, sensitive boolean not null default false, bank_overridable boolean not null default true, version int not null default 1, updated_at timestamptz default now());
create table plone27_bank_settings(bank_id uuid not null references plone27_banks, key text not null references plone27_settings, value jsonb not null, primary key(bank_id,key));
create table plone27_setting_changes(id uuid primary key default gen_random_uuid(), key text not null references plone27_settings, bank_id uuid references plone27_banks, new_value jsonb not null, old_value jsonb,
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
('api_default_rate_limit','integraciones','Peticiones por minuto de un cliente API nuevo','number',null,1,10000,'60',false,true);
create function plone27_setting(p_key text,p_bank uuid default null) returns jsonb language plpgsql stable security definer set search_path=public as $$ declare v jsonb; begin
 select coalesce((select b.value from plone27_bank_settings b where b.bank_id=p_bank and b.key=p_key),s.value) into v from plone27_settings s where s.key=p_key;
 if v is null then raise exception 'Ajuste desconocido: %',p_key; end if; return v; end $$;
create function plone27_setting_validate(p_key text,p_value jsonb) returns void language plpgsql stable as $$ declare s plone27_settings; begin
 select * into s from plone27_settings where key=p_key; if s.key is null then raise exception 'Ajuste desconocido'; end if;
 if s.vtype='number' then if jsonb_typeof(p_value)<>'number' or (p_value#>>'{}')::numeric<coalesce(s.min_v,-1e18) or (p_value#>>'{}')::numeric>coalesce(s.max_v,1e18) then raise exception 'Fuera de los límites centrales [% , %]',s.min_v,s.max_v; end if;
 elsif s.vtype='boolean' then if jsonb_typeof(p_value)<>'boolean' then raise exception 'Se esperaba booleano'; end if;
 elsif s.vtype='enum' then if not (p_value#>>'{}')=any(s.allowed) then raise exception 'Valor no permitido (%)',s.allowed; end if;
 elsif jsonb_typeof(p_value)<>'string' then raise exception 'Se esperaba texto'; end if; end $$;
create function plone27_setting_apply(p_change uuid,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare c plone27_setting_changes; begin
 select * into c from plone27_setting_changes where id=p_change and status='pending' for update; if c.id is null then return; end if;
 if c.bank_id is null then update plone27_settings set value=c.new_value,version=version+1,updated_at=now() where key=c.key;
 else insert into plone27_bank_settings values(c.bank_id,c.key,c.new_value) on conflict(bank_id,key) do update set value=c.new_value; end if;
 update plone27_setting_changes set status='applied',approved_by=coalesce(approved_by,p_actor) where id=p_change;
 insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'setting_applied','setting',c.key,jsonb_build_object('bank',c.bank_id,'new',c.new_value)); end $$;
create function plone27_setting_propose(p_key text,p_value jsonb,p_bank uuid,p_reason text,p_actor uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare s plone27_settings; id uuid; begin
 select * into s from plone27_settings where key=p_key; perform plone27_setting_validate(p_key,p_value);
 if p_bank is not null and not s.bank_overridable then raise exception 'Este ajuste solo es central'; end if; if coalesce(p_reason,'')='' then raise exception 'Motivo obligatorio'; end if;
 insert into plone27_setting_changes(key,bank_id,new_value,old_value,reason,proposed_by) values(p_key,p_bank,p_value,plone27_setting(p_key,p_bank),p_reason,p_actor) returning plone27_setting_changes.id into id;
 if not s.sensitive then perform plone27_setting_apply(id,p_actor); end if; return id; end $$;
create function plone27_setting_approve(p_change uuid,p_approve boolean,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare c plone27_setting_changes; begin
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
alter table plone27_tax_receipts add column disputed boolean not null default false;
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
create function plone27_apply_late_penalties(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$
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
