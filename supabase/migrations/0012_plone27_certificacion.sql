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
create trigger t_bracket_guard before insert or update or delete on plone27_tax_brackets for each row execute function plone27_bracket_guard();
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
