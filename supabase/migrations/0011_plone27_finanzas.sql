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
create trigger t_fee_cap before insert or update on plone27_fee_rules for each row execute function plone27_fee_cap();

-- ========== 3. MOTOR FISCAL: tramo fijo para cotizaciones, publicación con aprobador, impuestos de entidad ==========
alter table plone27_tax_rule_versions drop constraint if exists plone27_tax_rule_versions_method_check;
alter table plone27_tax_rule_versions add constraint plone27_tax_rule_versions_method_check
  check(method in('percent','fixed','brackets','bracket_flat'));  -- bracket_flat: todo el bruto al tipo de su tramo (Art. 4.5)

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
