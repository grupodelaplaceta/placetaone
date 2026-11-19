-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0024 · Diseños comprados por el usuario
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0023.
-- AÑADE: listado de diseños comprados por el usuario y aplicación de un diseño comprado a una tarjeta.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0024 · Diseños comprados por el usuario: listado y aplicación a sus tarjetas.
-- Requiere 0023. Idempotente.

-- Diseños comprados por el usuario en su entidad, con la cuenta que los compró y la fecha de la compra
create or replace function plone27_user_disenos_comprados(p_user uuid,p_bank uuid)
returns table(codigo text,nombre text,nivel text,rareza text,imagen_url text,animacion_url text,
              comprado timestamptz,cuenta_iban text,transaccion uuid,tarjetas_con_diseno int)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
    select d.codigo, d.name, d.tier, d.rareza, d.imagen_url, d.animacion_url,
           t.created_at, a.iban, p.tx,
           (select count(*)::int from plone27_cards cd where cd.design_id=d.id and cd.account_id=p.account_id)
    from plone27_design_purchases p
      join plone27_account_members m on m.account_id=p.account_id and m.user_id=p_user
      join plone27_accounts a on a.id=p.account_id and a.bank_id=p_bank
      join plone27_card_designs d on d.id=p.design_id
      left join plone27_transactions t on t.id=p.tx
    order by t.created_at desc nulls last, d.name;
end $$;

-- Aplica un diseño comprado por la cuenta de la tarjeta (o lo quita con p_codigo nulo)
create or replace function plone27_user_card_design(p_user uuid,p_bank uuid,p_ref text,p_codigo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; did uuid; begin
  select cd.* into c from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
    where cd.card_ref=p_ref and a.bank_id=p_bank;
  if c.id is null or not plone27_user_can(p_user,c.account_id,true,p_bank) then raise exception 'Tarjeta no encontrada'; end if;
  if c.status not in('active','suspended') then raise exception 'Esta tarjeta no admite cambios de diseño'; end if;
  if p_codigo is null then
    update plone27_cards set design_id=null where id=c.id;
  else
    select d.id into did from plone27_card_designs d where d.codigo=p_codigo;
    if did is null or not exists(select 1 from plone27_design_purchases p where p.design_id=did and p.account_id=c.account_id) then
      raise exception 'No has comprado este diseño para la cuenta de esta tarjeta';
    end if;
    update plone27_cards set design_id=did where id=c.id;
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'card_design','card',c.id::text,jsonb_build_object('persona',p_user,'diseno',p_codigo));
  return jsonb_build_object('diseno',p_codigo);
end $$;

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


do $$ begin raise notice 'Actualización 0024 aplicada correctamente.'; end $$;

commit;
