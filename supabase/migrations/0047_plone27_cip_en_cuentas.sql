-- Placeta One · 0047 · El CIP de la entidad institucional se informa en las cuentas (me/accounts y bk/cuentas).
-- cip_origen: "cuenta" si la cuenta es la de la entidad; "empresa" si pertenece a una empresa vinculada a la entidad.
-- Requiere 0046. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- Cambia la forma de la respuesta (dos columnas nuevas): hay que borrar la versión anterior
drop function if exists plone27_user_accounts(uuid,uuid);
create or replace function plone27_user_accounts(p_user uuid,p_bank uuid)
returns table(id uuid,iban text,nombre text,tipo text,rol text,saldo numeric,disponible numeric,cip text,cip_origen text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
  select a.id, a.iban, a.name, a.kind, m.role, b.booked, b.booked-b.reserved,
    coalesce(e.cip, ee.cip) as cip,
    case when e.cip is not null then 'cuenta' when ee.cip is not null then 'empresa' end as cip_origen
  from plone27_account_members m
  join plone27_accounts a on a.id=m.account_id
  join plone27_account_balances b on b.account_id=a.id
  left join plone27_entidades e on e.account_id=a.id
  left join lateral(
    select emp.entidad_cip as cip from plone27_empresa_cuentas ec
    join plone27_empresas emp on emp.id=ec.empresa_id
    where ec.account_id=a.id and emp.entidad_cip is not null limit 1) ee on true
  where m.user_id=p_user and a.status='active' and a.bank_id=p_bank
  order by a.created_at;
end $$;

-- Listado de cuentas de la entidad para el banco: mismo criterio de CIP
create or replace function plone27_bk_cuentas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.iban),'[]'::jsonb) from (
    select a.iban, a.name as nombre, a.kind as tipo, a.status as estado, plone27_available(a.id) as disponible,
      coalesce(e.cip, ee.cip) as cip,
      case when e.cip is not null then 'cuenta' when ee.cip is not null then 'empresa' end as cip_origen
    from plone27_accounts a
    left join plone27_entidades e on e.account_id=a.id
    left join lateral(
      select emp.entidad_cip as cip from plone27_empresa_cuentas ec
      join plone27_empresas emp on emp.id=ec.empresa_id
      where ec.account_id=a.id and emp.entidad_cip is not null limit 1) ee on true
    where a.bank_id=p_bank) x $$;

-- Seguridad (mismo patrón; no legibles desde el panel)
do $$ declare t text; f text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces','plone27_personas') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;
