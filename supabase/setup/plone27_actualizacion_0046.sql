-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0046 · Gestión completa por API de banco (delegaciones, reclamaciones del acreedor)
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0045.
-- ATENCIÓN: no ejecutada en PostgreSQL. Probar en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0046 · Gestión completa por API de banco: delegaciones de organigrama y reclamaciones del banco acreedor.
-- Requiere 0045. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- La unidad debe pertenecer a la entidad (CIP) del banco que llama
create or replace function plone27_org_unidad_valida(p_bank uuid,p_cip text,p_unidad uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_unidades u join plone27_entidades e on e.account_id=u.entidad
    where u.id=p_unidad and e.cip=p_cip and e.bank_id=p_bank) $$;

create or replace function plone27_org_delegar(p_bank uuid,p_cip text,p_actor uuid,p_unidad uuid,p_persona uuid,p_permiso text,
    p_limite numeric,p_hasta date,p_motivo text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_org_unidad_valida(p_bank,p_cip,p_unidad) then raise exception 'La unidad no pertenece a esta entidad'; end if;
  perform plone27_delegar(p_unidad,p_persona,p_permiso,p_limite,p_hasta,p_motivo,p_actor);
end $$;

create or replace function plone27_org_revocar_delegacion(p_bank uuid,p_cip text,p_actor uuid,p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not exists(select 1 from plone27_delegaciones d join plone27_unidades u on u.id=d.unidad
                join plone27_entidades e on e.account_id=u.entidad where d.id=p_id and e.cip=p_cip and e.bank_id=p_bank) then
    raise exception 'La delegación no pertenece a esta entidad';
  end if;
  perform plone27_revocar_delegacion(p_id,p_actor);
end $$;

-- Reclamaciones que afectan al banco: como acreedor (debe devolver) o como deudor (su cliente reclama)
create or replace function plone27_bk_disputas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.creada desc),'[]'::jsonb) from (
    select dsp.id, dsp.debt_id, dsp.estado, dsp.monto_reclamado, dsp.monto_devuelto, dsp.motivo, dsp.plazo_resolucion, dsp.creada,
      case when ca.bank_id=p_bank then 'acreedor' else 'deudor' end as rol
    from plone27_disputas dsp
    join plone27_debts dd on dd.id=dsp.debt_id
    join plone27_accounts ca on ca.id=dd.creditor_account
    join plone27_accounts da on da.id=dsp.account_id
    where ca.bank_id=p_bank or da.bank_id=p_bank) r $$;

-- Solo el banco acreedor resuelve. El operador identifica a la persona del banco: dos operadores distintos para devoluciones grandes.
create or replace function plone27_bk_disputa_resolver(p_bank uuid,p_id uuid,p_decision text,p_monto numeric,p_operador text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_debts; ca uuid; begin
  select dd.* into d from plone27_disputas dsp join plone27_debts dd on dd.id=dsp.debt_id where dsp.id=p_id;
  if d.id is null then raise exception 'Reclamación no encontrada'; end if;
  select a.bank_id into ca from plone27_accounts a where a.id=d.creditor_account;
  if ca is distinct from p_bank then raise exception 'Solo el banco acreedor puede resolver esta reclamación'; end if;
  if coalesce(length(p_operador),0)<1 then raise exception 'Indica el operador que resuelve'; end if;
  return plone27_disputa_resolver(p_id,p_decision,p_monto,md5(p_bank::text||':'||p_operador)::uuid);
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


do $$ begin raise notice 'Actualización 0046 aplicada correctamente.'; end $$;

commit;
