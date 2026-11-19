-- Placeta One · seed 0013 · Cuentas institucionales. Ejecutar después de 0012 y de los seeds 0011 y 0012.
-- Crea la cuenta de Tributos (IBAN propia), fija el origen de la RBU y los destinos por impuesto.
-- Las cuentas institucionales quedan SIN aprobador registrado: regístralo con plone27_institutional_set (el informe lo avisa).

do $$ declare bk uuid; tr uuid; begin
  select id into bk from plone27_banks where code='0000';
  if not exists(select 1 from plone27_config where key='cuenta_tributos') then
    tr:=(plone27_open_account(bk,'system','Tributos · cuenta institucional',null,null)->>'id')::uuid;
    insert into plone27_config(key,value) values('cuenta_tributos',tr::text);
  end if;
  if not exists(select 1 from plone27_config where key='cuenta_rbu_origen') then
    insert into plone27_config(key,value) select 'cuenta_rbu_origen',value from plone27_config where key='cuenta_reserva';
  end if;
end $$;

-- Destino por defecto de los impuestos: Tributos. Las cotizaciones siguen en la Reserva (Art. 4.5).
update plone27_tax_rules set collector_account=(select nullif(value,'')::uuid from plone27_config where key='cuenta_tributos')
  where code not in('COT_EMP','COT_TRA');

-- Cuentas institucionales de partida (sin aprobador: pendiente de registrar)
insert into plone27_institutional_accounts(account_id,motivo,puede_operar_junior,aprobado_por)
select (select nullif(value,'')::uuid from plone27_config where key=v.k), v.m, v.j, null from (values
  ('cuenta_reserva','Cuenta de Reserva del Grupo: cotizaciones y fondos de la RBU',false),
  ('cuenta_tributos','Cuenta de Tributos: recaudación de los impuestos',false),
  ('cuenta_placeta_junior','Placeta Junior · pagos asumidos: pagador Junior si Capitalia no paga',true)
) as v(k,m,j)
on conflict(account_id) do nothing;

do $$ begin
  assert not exists(select 1 from plone27_tax_rules where collector_account is null), 'Todo impuesto necesita destino';
  assert (select count(*) from plone27_institutional_accounts) >= 3, 'Faltan cuentas institucionales';
end $$;
