-- Placeta One · 0015 · Previsión de movimientos programados e indicadores del panel. Requiere 0014. Idempotente.

-- Previsión: todo lo que va a ocurrir en un rango de fechas, con si la cuenta puede pagarlo.
create or replace function plone27_previsiones(p_desde date,p_hasta date) returns table(
  fecha date, tipo text, referencia text, cuenta uuid, iban text, nombre text, importe numeric, estado text, detalle text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
  select u.* from (
    -- Impuestos: recibos pendientes (vencidos o con vencimiento en el rango)
    select r.due_date, 'Impuesto'::text, (ru.code||' · '||coalesce(r.ref,'sin referencia'))::text, r.account_id, a.iban, a.name,
           (r.amount-r.paid_amount)::numeric,
           (case when r.due_date<current_date then 'vencido'
                 when plone27_collectable(r.account_id,r.amount-r.paid_amount) then 'cobrable' else 'sin fondos' end)::text,
           ('Vence el '||r.due_date::text)::text
    from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
      join plone27_tax_rules ru on ru.id=v.rule_id join plone27_accounts a on a.id=r.account_id
    where r.status in('issued','partial') and r.amount-r.paid_amount>0 and r.due_date between p_desde and p_hasta
    union all
    -- Cuotas de planes a plazos
    select i.due_date, 'Cuota'::text, ('Plan '||left(p.id::text,8)||' · cuota '||i.seq)::text, p.debtor_account, a.iban, a.name,
           (i.principal_part+i.interest_part)::numeric,
           (case when i.due_date<current_date then 'vencido'
                 when plone27_collectable(p.debtor_account,i.principal_part+i.interest_part) then 'cobrable' else 'sin fondos' end)::text,
           ('Capital '||i.principal_part::text||' · interés '||i.interest_part::text)::text
    from plone27_plan_items i join plone27_plans p on p.id=i.plan_id join plone27_accounts a on a.id=p.debtor_account
    where i.status='pending' and p.status in('active','past_due') and i.due_date between p_desde and p_hasta
    union all
    -- Suscripciones: próximo cobro
    select p.next_due, 'Suscripción'::text, ('Suscripción '||left(p.id::text,8))::text, p.debtor_account, a.iban, a.name, p.principal::numeric,
           (case when plone27_collectable(p.debtor_account,p.principal) then 'cobrable' else 'sin fondos' end)::text,
           'Cobro periódico al beneficiario'::text
    from plone27_plans p join plone27_accounts a on a.id=p.debtor_account
    where p.kind='subscription' and p.status in('active','past_due') and p.next_due between p_desde and p_hasta
    union all
    -- Nóminas: bruto más cotización de empresa, desde la cuenta empleadora
    select c.next_pay, 'Nómina'::text, ('Contrato '||left(c.id::text,8))::text, c.employer_account, a.iban, a.name,
           (c.gross_monthly+coalesce(plone27_tax_calc(plone27_active_version('COT_EMP',c.next_pay),c.gross_monthly),0))::numeric,
           (case when plone27_collectable(c.employer_account,c.gross_monthly+coalesce(plone27_tax_calc(plone27_active_version('COT_EMP',c.next_pay),c.gross_monthly),0))
                 then 'cobrable' else 'sin fondos' end)::text,
           'Bruto más cotización de empresa'::text
    from plone27_contracts c join plone27_accounts a on a.id=c.employer_account
    where c.status='active' and c.next_pay between p_desde and p_hasta
    union all
    -- Transferencias programadas, con sus repeticiones dentro del rango (hasta 240)
    select (s.run_at+k.n*coalesce(s.recurrence,interval '0'))::date, 'Transferencia programada'::text, coalesce(s.memo,'Programada')::text,
           s.from_account, a.iban, a.name, s.amount::numeric,
           (case when plone27_collectable(s.from_account,s.amount) then 'cobrable' else 'sin fondos' end)::text,
           (case when s.recurrence is null then 'Única' else 'Recurrente' end)::text
    from plone27_scheduled s join plone27_accounts a on a.id=s.from_account
      cross join lateral generate_series(0, case when s.recurrence is null then 0 else 240 end) k(n)
    where s.status='active' and (s.run_at+k.n*coalesce(s.recurrence,interval '0'))::date between p_desde and p_hasta
    union all
    -- Cierres mensuales (el del mes en curso y el siguiente)
    select x.f, 'Cierre mensual'::text, ('Cierre de '||to_char(x.m-interval '1 month','YYYY-MM'))::text, null::uuid, null::text, null::text, null::numeric,
           (case when exists(select 1 from plone27_periodos pp where pp.periodo=(x.m-interval '1 month')::date and pp.estado='cerrado')
                 then 'cerrado' else 'programado' end)::text,
           'Liquida el IVA y los impuestos periódicos del mes anterior'::text
    from (select make_date(extract(year from ms.m)::int, extract(month from ms.m)::int,
                 (plone27_setting('dia_cierre')#>>'{}')::int) f, ms.m
          from (select date_trunc('month',current_date) m union all select date_trunc('month',current_date)+interval '1 month') ms) x
    where x.f between p_desde and p_hasta
    union all
    -- IAEP: cuota fija de cada actividad, emitida el día 1 de cada mes
    select (date_trunc('month',current_date)+interval '1 month')::date, 'IAEP mensual'::text,
           ('Actividades activas: '||count(*))::text, null::uuid, null::text, null::text, coalesce(sum(v.rate),0)::numeric,
           'estimado'::text, 'Cuota fija por categoría'::text
    from plone27_activities a join plone27_tax_rules ru on ru.code='IAEP'
      join plone27_tax_rule_versions v on v.rule_id=ru.id and v.scope_op=a.category and v.status='published'
    where a.status='active' and (date_trunc('month',current_date)+interval '1 month')::date between p_desde and p_hasta
    having count(*)>0
    union all
    -- Deudas reconocidas (incluidos intereses de demora y recargos)
    select d.due_date, 'Deuda'::text, coalesce(d.reason,'Deuda')::text, d.account_id, a.iban, a.name,
           (d.principal+d.authorized_charges-d.paid)::numeric,
           (case when d.due_date<current_date then 'vencido'
                 when plone27_collectable(d.account_id,d.principal+d.authorized_charges-d.paid) then 'cobrable' else 'sin fondos' end)::text,
           'Deuda reconocida'::text
    from plone27_debts d join plone27_accounts a on a.id=d.account_id
    where not d.disputed and d.paid<d.principal+d.authorized_charges and d.due_date between p_desde and p_hasta
    union all
    -- RBU sin reclamar: caduca en esa fecha
    select b.expires_on, 'RBU sin reclamar'::text, ('Bono semana '||b.week_start::text)::text, b.wallet_account, a.iban, a.name, b.amount::numeric,
           'disponible'::text, 'Si no se reclama, caduca'::text
    from plone27_rbu_bonuses b join plone27_accounts a on a.id=b.wallet_account
    where b.status='available' and b.expires_on between p_desde and p_hasta
    union all
    -- IVA estimado del mes en curso: base devengada por el tipo general (sin deducir compras)
    select (date_trunc('month',current_date)+interval '1 month -1 day')::date, 'IVA estimado'::text, 'Mes en curso'::text,
           null::uuid, null::text, null::text,
           round(coalesce((select sum(s.base) from plone27_sales s where s.created_at>=date_trunc('month',current_date)
                           and s.created_at<date_trunc('month',current_date)+interval '1 month'),0)
                 *coalesce((select v.rate from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id
                            where ru.code='IVA' and v.status='published' and v.scope_op is null order by v.valid_from desc limit 1),0)/100,2)::numeric,
           'estimado'::text, 'Base devengada del mes × tipo general, sin deducir compras'::text
    where (date_trunc('month',current_date)+interval '1 month -1 day')::date between p_desde and p_hasta
  ) u order by u.fecha, u.tipo;
end $$;

-- Indicadores para el panel principal
create or replace function plone27_kpis() returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'recibos_pendientes',(select count(*) from plone27_tax_receipts where status in('issued','partial')),
    'recibos_pendientes_importe',(select coalesce(sum(amount-paid_amount),0) from plone27_tax_receipts where status in('issued','partial')),
    'recibos_vencidos',(select count(*) from plone27_tax_receipts where status in('issued','partial') and due_date<current_date),
    'cuentas_activas',(select count(*) from plone27_accounts where status='active'),
    'planes_activos',(select count(*) from plone27_plans where status in('active','past_due')),
    'cuotas_pendientes_importe',(select coalesce(sum(principal_part+interest_part),0) from plone27_plan_items where status='pending'),
    'contratos_activos',(select count(*) from plone27_contracts where status='active'),
    'rbu_disponible',(select coalesce(sum(amount),0) from plone27_rbu_bonuses where status='available'),
    'hallazgos_iva_abiertos',(select count(*) from plone27_iva_findings where status in('abierto','presumido')),
    'declaraciones_retenidas',(select count(*) from plone27_declaraciones where estado='retenida'),
    'incidencias_abiertas',(select count(*) from plone27_incidents where status='open'),
    'certificacion',(plone27_certification_report()->>'estado'),
    'ultimo_cierre',(select max(periodo) from plone27_periodos where estado='cerrado'))
$$;
