-- Placeta One · 0077 · Las denuncias las registra Justicia (organismo externo), no los bancos.
-- Justicia es una entidad propia, sin cuentas de dinero, con su propia clave y solo el permiso de denuncias.
-- Requiere 0076. Idempotente. NO ejecutado en PostgreSQL.

-- Entidad de Justicia (debe existir con ese nombre; la crea la Junta desde Bancos y le da su clave)
create or replace function plone27_banco_justicia() returns uuid
language plpgsql stable security definer set search_path=public as $$
declare b uuid; begin
  select id into b from plone27_banks where name='Justicia (externo)';
  if b is null then raise exception 'Falta la entidad "Justicia (externo)": créala en Bancos con ese nombre y dale su clave'; end if;
  return b; end $$;

-- Denunciar: solo Justicia. Ya no depende del banco de la cuenta.
create or replace function plone27_sancion_denunciar(p_bank uuid,p_sancion uuid,p_dip text,p_texto text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; did uuid; d text; begin
  if p_bank is distinct from plone27_banco_justicia() then raise exception 'Solo Justicia registra denuncias'; end if;
  select * into s from plone27_sanciones where id=p_sancion for update;
  if s.id is null then raise exception 'Sanción no encontrada'; end if;
  if s.estado<>'notificada' then raise exception 'Solo se puede denunciar una sanción notificada'; end if;
  if now()>s.plazo_recurso_hasta then raise exception 'El plazo para denunciar ha terminado'; end if;
  if coalesce(length(p_texto),0)<20 then raise exception 'La denuncia debe explicar los hechos (mínimo 20 caracteres)'; end if;
  d:=plone27_normalizar_dip(p_dip);
  if not (
       exists(select 1 from plone27_accounts a join plone27_customers c on c.id=a.customer_id where a.id=s.cuenta and c.dip=d)
    or exists(select 1 from plone27_joven_cuentas jc where jc.account_id=s.cuenta and jc.dip=d)
    or (s.cuenta_origen is not null and exists(select 1 from plone27_accounts a join plone27_customers c on c.id=a.customer_id where a.id=s.cuenta_origen and c.dip=d))
  ) then raise exception 'Solo la persona sancionada o su tutor pueden denunciar'; end if;
  insert into plone27_denuncias(sancion,dip,texto) values(p_sancion,d,p_texto) returning plone27_denuncias.id into did;
  update plone27_sanciones set estado='recurrida', recurso_motivo=left(p_texto,500) where id=p_sancion;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_denuncia','sancion',p_sancion::text,jsonb_build_object('denuncia',did,'via','justicia'));
  return did; end $$;

-- Sanciones notificadas de una persona, para que Justicia sepa qué puede denunciar
create or replace function plone27_justicia_sanciones_de(p_bank uuid,p_dip text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare d text; begin
  if p_bank is distinct from plone27_banco_justicia() then raise exception 'Solo Justicia consulta sanciones'; end if;
  d:=plone27_normalizar_dip(p_dip);
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.plazo_recurso_hasta) from (
    select s.id as sancion, s.tipo, s.importe, s.motivo, s.norma, s.notificada_at, s.plazo_recurso_hasta
    from plone27_sanciones s
    where s.estado='notificada' and s.plazo_recurso_hasta>now()
      and (exists(select 1 from plone27_accounts a join plone27_customers c on c.id=a.customer_id where a.id=s.cuenta and c.dip=d)
        or exists(select 1 from plone27_joven_cuentas jc where jc.account_id=s.cuenta and jc.dip=d)
        or (s.cuenta_origen is not null and exists(select 1 from plone27_accounts a join plone27_customers c on c.id=a.customer_id where a.id=s.cuenta_origen and c.dip=d)))
  ) x), '[]'::jsonb); end $$;

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
