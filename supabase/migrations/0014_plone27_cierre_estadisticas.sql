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
alter table plone27_sales add constraint plone27_sales_origin_check check(origin in('plataforma','regularizada','presunta'));
alter table plone27_iva_findings drop constraint if exists plone27_iva_findings_status_check;
alter table plone27_iva_findings add constraint plone27_iva_findings_status_check check(status in('abierto','presumido','regularizado','descartado'));
alter table plone27_tax_certificates drop constraint if exists plone27_tax_certificates_kind_check;
alter table plone27_tax_certificates add constraint plone27_tax_certificates_kind_check check(kind in('recibo','regularizacion','recargo','rectificacion','cierre'));

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
