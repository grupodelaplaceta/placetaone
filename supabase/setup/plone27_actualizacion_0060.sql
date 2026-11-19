begin;
-- Placeta One · 0060 · Los bonos RBU caducan a los 3 meses de su emisión si no se canjean.
-- Antes caducaban a los 7 días. Los bonos disponibles existentes se extienden al nuevo plazo.
-- Requiere 0059. Idempotente. NO ejecutado en PostgreSQL.

create or replace function plone27_rbu_issue_week(p_week date,p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u record; wal uuid; bk uuid; n int:=0; amt numeric:=(plone27_setting('rbu_semanal_pz')#>>'{}')::numeric; begin
  for u in select distinct m.user_id from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where a.kind='personal' and a.status='active' and m.role='holder'
      and not exists(select 1 from plone27_customers c join plone27_junior_profiles j on j.customer_id=c.id where c.user_id=m.user_id)
  loop
    continue when exists(select 1 from plone27_rbu_bonuses where owner_user=u.user_id and week_start=p_week);
    select a.bank_id into bk from plone27_accounts a join plone27_account_members m on m.account_id=a.id
      where m.user_id=u.user_id and a.kind='personal' and a.status='active' and a.name is distinct from 'RBU · cartera'
      order by a.created_at limit 1;
    wal:=plone27_user_cuenta_principal(u.user_id,bk);
    continue when wal is null;
    insert into plone27_rbu_bonuses(owner_user,wallet_account,week_start,amount,expires_on)
      values(u.user_id,wal,p_week,amt,(p_week+interval '3 months')::date);
    n:=n+1;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'rbu_emision','rbu',p_week::text,jsonb_build_object('bonos',n,'caducidad_meses',3));
  return n; end $$;

-- Bonos disponibles existentes: se alinean al nuevo plazo de 3 meses desde su semana de emisión
update plone27_rbu_bonuses
  set expires_on=(week_start+interval '3 months')::date
  where status='available' and expires_on<(week_start+interval '3 months')::date;

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

do $$ begin raise notice 'Actualización 0060 aplicada correctamente.'; end $$;

commit;
