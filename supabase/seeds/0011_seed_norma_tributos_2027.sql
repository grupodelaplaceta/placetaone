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
