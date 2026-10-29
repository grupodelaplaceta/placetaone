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
insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(null,'decision','setting','capitalia_asume_impuestos_junior',
  jsonb_build_object('valor',true,'texto','Capitalia paga en nombre de los usuarios Junior los impuestos mensuales y cualquier otro. El obligado sigue siendo el usuario Junior.'));

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
alter table plone27_tax_certificates add constraint plone27_tax_certificates_kind_check
  check(kind in('recibo','regularizacion','recargo','rectificacion'));
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
    join lateral (select k.amount,k.base from plone27_tax_certificates k where k.subject_id=r.id order by k.seq desc limit 1) u on true
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
