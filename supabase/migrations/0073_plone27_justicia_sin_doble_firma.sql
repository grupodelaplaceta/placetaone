-- Placeta One · 0073 · Sanciones sin doble aprobación (la Junta son 4 personas y la mayoría no usa el sistema),
-- sanciones a cuentas Junior en la cuenta del tutor, sanciones a cuentas Joven (normas Joven),
-- y multas a administración o a tributos. Requiere 0072. Idempotente. NO ejecutado en PostgreSQL.

-- 1) Fuera las restricciones de doble firma de la tabla
do $$ declare r record; begin
  for r in select c.conname from pg_constraint c join pg_class t on t.oid=c.conrelid
    where t.relname='plone27_sanciones' and c.contype='c'
      and (pg_get_constraintdef(c.oid) like '%aprobada_por%' or pg_get_constraintdef(c.oid) like '%ejecutada_por%') loop
    execute format('alter table plone27_sanciones drop constraint %I', r.conname);
  end loop;
end $$;
alter table plone27_sanciones add column if not exists cuenta_origen uuid references plone27_accounts(id);

-- 2) Guardián Joven: una sanción puede tocar una cuenta congelada (la congelación es por suscripción, no por sanción)
create or replace function plone27_joven_guard() returns trigger language plpgsql as $$
#variable_conflict use_column
declare malas int; congeladas int; begin
  if exists(select 1 from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
            where e.transaction_id=new.transaction_id and a.kind='joven') then
    if coalesce(current_setting('plone27.joven_op', true),'')<>'on' then
      raise exception 'Las cuentas Placeta Joven solo se operan desde Placeta Joven';
    end if;
    select count(*) into congeladas from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
      join plone27_joven_cuentas jc on jc.account_id=a.id
      where e.transaction_id=new.transaction_id and jc.congelada;
    if congeladas>0 and coalesce(current_setting('plone27.sancion', true),'')<>'on' then
      raise exception 'Cuenta Placeta Joven congelada: no admite movimientos';
    end if;
    select count(*) into malas from plone27_ledger_entries e join plone27_accounts a on a.id=e.account_id
      where e.transaction_id=new.transaction_id and a.kind<>'joven'
        and not (a.kind='system' or (a.kind='business' and a.comercio_joven));
    if malas>0 then
      raise exception 'Placeta Joven: el dinero solo puede moverse entre cuentas Joven, administración o comercios Joven';
    end if;
  end if;
  return null; end $$;

-- 3) Proponer: la sanción queda aprobada al proponerla. Junior -> cuenta del tutor. Multas a administración o tributos.
create or replace function plone27_sancion_proponer(p_bank uuid,p_tipo text,p_iban text,p_importe numeric,p_motivo text,
    p_norma text,p_iban_destino text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c uuid; k text; origen uuid; tutor uuid; cobro uuid; d uuid; sid uuid; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta puede proponer sanciones'; end if;
  if p_tipo not in('multa','incautacion','embargo') then raise exception 'Tipo no válido (multa, incautacion o embargo)'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'El importe debe ser mayor que cero'; end if;
  if coalesce(length(p_motivo),0)<20 then raise exception 'El motivo debe explicar el hecho (mínimo 20 caracteres)'; end if;
  if coalesce(length(p_norma),0)<5 then raise exception 'Indica la norma que respalda la sanción'; end if;
  select a.id, a.kind into c, k from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if c is null then raise exception 'La cuenta no pertenece a tu entidad'; end if;
  if k='system' then raise exception 'Una cuenta de administración no puede ser objeto de sanción'; end if;
  cobro:=c;
  if k='junior' then
    select g.guardian_user into tutor from plone27_juniors g where g.account_id=c;
    if tutor is null then raise exception 'La cuenta junior no tiene tutor: la sanción no puede aplicarse'; end if;
    cobro:=plone27_user_cuenta_principal(tutor,p_bank);
    if cobro is null then raise exception 'El tutor no tiene cuenta personal en la entidad'; end if;
    origen:=c;
  end if;
  if p_tipo in('multa','incautacion') then
    select a.id into d from plone27_accounts a where a.iban=p_iban_destino and a.bank_id=p_bank
      and (a.kind='system' or a.id in(select r.collector_account from plone27_tax_rules r where r.collector_account is not null));
    if d is null then raise exception 'El destino debe ser una cuenta de administración o de tributos de tu entidad'; end if;
  end if;
  insert into plone27_sanciones(bank_id,tipo,cuenta,cuenta_origen,destino,importe,motivo,norma,propuesta_por,estado,aprobada_por)
    values(p_bank,p_tipo,cobro,origen,d,p_importe,p_motivo,p_norma,p_actor,'aprobada',p_actor) returning plone27_sanciones.id into sid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'sancion_proponer','sancion',sid::text,jsonb_build_object('tipo',p_tipo,'importe',p_importe,'cuenta_origen',origen));
  return sid; end $$;

-- La aprobación separada ya no existe
drop function if exists plone27_sancion_aprobar(uuid,uuid);

-- 4) Resolver el recurso: la Junta sola
create or replace function plone27_sancion_resolver_recurso(p_id uuid,p_confirmar boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta resuelve recursos'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'recurrida' then raise exception 'La sanción no tiene un recurso pendiente'; end if;
  if p_confirmar then
    update plone27_sanciones set estado='firme', resolucion_recurso='confirmada' where id=p_id;
  else
    if s.reserva is not null then perform plone27_release(s.reserva,p_actor); end if;
    update plone27_sanciones set estado='anulada', resolucion_recurso='anulada' where id=p_id;
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_resolver_recurso','sancion',p_id::text,jsonb_build_object('confirmada',p_confirmar)); end $$;

-- 5) Ejecutar: la Junta sola. Multa a cuenta Joven = cobro al momento (no deuda), con la marca de sanción.
create or replace function plone27_sancion_ejecutar(p_id uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; k text; inemb numeric; disp numeric; maxi numeric; tx uuid; rid uuid; did uuid; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta ejecuta sanciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'firme' then raise exception 'La sanción no está firme'; end if;
  select a.kind into k from plone27_accounts a where a.id=s.cuenta;
  perform set_config('plone27.sancion','on',true);
  if k='joven' then perform set_config('plone27.joven_op','on',true); end if;
  inemb:=(plone27_setting('sancion_inembargable_pz')#>>'{}')::numeric;
  disp:=plone27_available(s.cuenta);
  maxi:=greatest(disp-inemb,0);
  if s.tipo='multa' and k<>'joven' then
    insert into plone27_debts(account_id,principal,due_date,authorized_by,reason,creditor_account)
      values(s.cuenta,s.importe,current_date+15,p_actor,'Multa: '||s.motivo,s.destino) returning plone27_debts.id into did;
    update plone27_sanciones set estado='ejecutada', deuda=did, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
    return jsonb_build_object('tipo','multa','deuda',did);
  end if;
  if s.tipo in('multa','incautacion') then
    if s.importe>maxi then raise exception 'Solo es cobrable hasta % Pz: el resto es inembargable', maxi; end if;
    tx:=plone27_transfer('sancion:'||s.id::text,s.cuenta,s.destino,s.importe,
      case when s.tipo='multa' then 'Multa: ' else 'Incautación: ' end||left(s.motivo,80),p_actor);
    update plone27_sanciones set estado='ejecutada', transaccion=tx, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
    return jsonb_build_object('tipo',s.tipo,'transaccion',tx);
  end if;
  if s.importe>maxi then raise exception 'Solo es embargable hasta % Pz: el resto es inembargable', maxi; end if;
  rid:=plone27_reserve(s.cuenta,s.importe,'Embargo: '||left(s.motivo,80),p_actor);
  update plone27_sanciones set estado='ejecutada', reserva=rid, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
  return jsonb_build_object('tipo','embargo','reserva',rid); end $$;

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
