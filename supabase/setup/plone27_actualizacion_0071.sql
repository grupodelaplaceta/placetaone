begin;
-- Placeta One · 0071 · Al pasar de Junior a Joven: el tutor desaparece; la cuenta junior pasa a personal;
-- la cuenta Joven es NUEVA y aislada (no comparte saldo ni historial con la cuenta personal).
-- Requiere 0070. Idempotente. NO ejecutado en PostgreSQL.

-- El tutor deja de ser obligatorio (se quita al pasar a Joven)
alter table plone27_junior_profiles alter column guardian_user drop not null;
alter table plone27_juniors alter column guardian_user drop not null;

create or replace function plone27_joven_promover(p_bank uuid,p_dip text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cust uuid; aid uuid; iban_j text; nac date; per uuid; n int; vc text; iban_nueva text; nueva uuid; begin
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

  -- 1) Cuenta Joven nueva y aislada
  select b.code into vc from plone27_banks b where b.id=p_bank;
  iban_nueva:='PZ-'||vc||'-'||lpad(plone27_next_num('ACC',vc,9999)::text,4,'0');
  insert into plone27_accounts(bank_id,kind,name,iban) values(p_bank,'joven','Placeta Joven',iban_nueva)
    returning plone27_accounts.id into nueva;
  insert into plone27_joven_cuentas(account_id,bank_id,persona,dip,fecha_nacimiento)
    values(nueva,p_bank,per,plone27_normalizar_dip(p_dip),nac);

  -- 2) La cuenta junior pasa a personal y pierde al tutor
  update plone27_accounts set kind='personal' where id=aid;
  update plone27_junior_profiles set guardian_user=null where customer_id=cust;
  update plone27_juniors set guardian_user=null where account_id=aid;

  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'joven_promocion','persona',per::text,jsonb_build_object(
      'iban_joven',iban_nueva,'iban_personal',iban_j,'tutor_retirado',true));
  return jsonb_build_object('iban_joven',iban_nueva,'iban_personal',iban_j,
    'cuenta_junior_convertida_a','personal','tutor_retirado',true,'promovida',true); end $$;

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

do $$ begin raise notice 'Actualización 0071 aplicada correctamente.'; end $$;

commit;
