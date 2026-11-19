-- Placeta One · 0062 · Aprobación automática de productos: un producto marcado se activa solo al guardarlo.
-- La activación manual no cambia. Requiere 0061. Idempotente. NO ejecutado en PostgreSQL.

alter table plone27_products add column if not exists aprobacion_automatica boolean not null default false;

-- Guardián: un producto con aprobación automática pasa a activo; activar exige quien lo registra.
create or replace function plone27_product_guard() returns trigger language plpgsql as $$
#variable_conflict use_column
begin
  if new.aprobacion_automatica and new.status='draft' then
    new.status:='active';
  end if;
  if tg_op='UPDATE' and new.status is distinct from old.status then
    if (old.status,new.status) not in (('draft','active'),('active','retired'),('draft','retired')) then
      raise exception 'Transición de producto % → % no permitida', old.status, new.status;
    end if;
  end if;
  if (tg_op='INSERT' or new.status is distinct from old.status) and new.status='active' and new.approved_by is null then
    raise exception 'Activar un producto requiere aprobación registrada';
  end if;
  return new; end $$;

-- Reemplaza el disparador existente por uno que se ejecuta en alta y en modificación
do $$ declare r record; begin
  for r in select t.tgname from pg_trigger t
           join pg_proc p on p.oid=t.tgfoid join pg_class c on c.oid=t.tgrelid
           where c.relname='plone27_products' and p.proname='plone27_product_guard' and not t.tgisinternal loop
    execute format('drop trigger %I on plone27_products', r.tgname);
  end loop;
end $$;
create trigger trg_product_guard before insert or update on plone27_products
  for each row execute function plone27_product_guard();

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
