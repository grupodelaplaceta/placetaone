-- Placeta One · seed 0012 · Recargos T57 (Art. T57). Ejecutar después de 0011 y de su seed. Entra en BORRADOR.
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
