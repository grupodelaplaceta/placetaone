begin;
-- Placeta One · 0070 · Pasar de cuenta Junior a Placeta Joven: solo a partir de 16 años cumplidos.
-- La misma cuenta cambia de tipo (conserva IBAN, saldo e historial). La fecha de nacimiento sale de la ficha junior.
-- Requiere 0069. Idempotente. NO ejecutado en PostgreSQL.

create or replace function plone27_joven_promover(p_bank uuid,p_dip text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cust uuid; aid uuid; iban_j text; nac date; per uuid; n int; begin
  if p_bank is distinct from plone27_banco_joven() then raise exception 'Solo Banco de La Placeta opera Placeta Joven'; end if;
  select c.id into cust from plone27_customers c where c.dip=plone27_normalizar_dip(p_dip);
  if cust is null then raise exception 'No existe ninguna persona con ese DIP'; end if;
  select count(*) into n from plone27_accounts a where a.customer_id=cust and a.kind='junior' and a.bank_id=p_bank;
  if n=0 then raise exception 'Esta persona no tiene cuenta Junior en tu entidad'; end if;
  if n>1 then raise exception 'Esta persona tiene más de una cuenta Junior: hay que revisarla a mano'; end if;
  select a.id, a.iban into aid, iban_j from plone27_accounts a where a.customer_id=cust and a.kind='junior' and a.bank_id=p_bank;
  select jp.birth_date into nac from plone27_junior_profiles jp where jp.customer_id=cust;
  if nac is null then raise exception 'Falta la fecha de nacimiento en la ficha junior'; end if;
  if age(current_date,nac)<interval '16 years' then
    raise exception 'Para pasar de Junior a Placeta Joven hay que tener 16 años cumplidos';
  end if;
  if not plone27_joven_vigente(nac) then
    raise exception 'Fuera de la edad Placeta Joven (16 a 31 años; el periodo de gracia termina el 31 de diciembre del año en que se cumplen 31)';
  end if;
  per:=plone27_persona(p_dip);
  if exists(select 1 from plone27_joven_cuentas where bank_id=p_bank and persona=per) then
    raise exception 'Esta persona ya tiene cuenta Placeta Joven';
  end if;
  update plone27_accounts set kind='joven', comercio_joven=false where id=aid;
  insert into plone27_joven_cuentas(account_id,bank_id,persona,dip,fecha_nacimiento)
    values(aid,p_bank,per,plone27_normalizar_dip(p_dip),nac);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'joven_promocion','account',aid::text,jsonb_build_object('iban',iban_j,'desde','junior'));
  return jsonb_build_object('iban',iban_j,'promovida',true,'disponible',plone27_available(aid)); end $$;

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

do $$ begin raise notice 'Actualización 0070 aplicada correctamente.'; end $$;

commit;
