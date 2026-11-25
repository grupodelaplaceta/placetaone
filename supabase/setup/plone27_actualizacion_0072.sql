begin;
-- Placeta One · 0072 · Sanciones: multas, incautaciones y embargos, con doble firma, notificación, recurso e inembargable.
-- Solo la Junta. Requiere 0071. Idempotente. NO ejecutado en PostgreSQL.

-- Ajustes del módulo (sensibles: doble firma)
insert into plone27_settings(key,category,description,vtype,min_v,max_v,value,sensitive,bank_overridable) values
  ('sancion_plazo_recurso_dias','justicia','Días para recurrir una sanción desde su notificación','number',10,90,'30',true,false),
  ('sancion_inembargable_pz','justicia','Saldo inembargable de una cuenta (Pz): nunca se incauta ni embarga por debajo de esta cantidad','number',0,100000,'160',true,false)
on conflict (key) do nothing;

create table if not exists plone27_sanciones(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks(id),
  tipo text not null check(tipo in('multa','incautacion','embargo')),
  cuenta uuid not null references plone27_accounts(id),
  destino uuid references plone27_accounts(id),
  importe numeric(18,2) not null check(importe>0),
  motivo text not null check(length(motivo)>=20),
  norma text not null check(length(norma)>=5),
  estado text not null default 'propuesta' check(estado in('propuesta','aprobada','notificada','recurrida','firme','ejecutada','anulada')),
  propuesta_por uuid not null,
  aprobada_por uuid,
  notificada_at timestamptz,
  plazo_recurso_hasta timestamptz,
  recurso_motivo text,
  resolucion_recurso text check(resolucion_recurso in('confirmada','anulada')),
  ejecutada_por uuid,
  ejecutada_at timestamptz,
  transaccion uuid references plone27_transactions(id),
  reserva uuid references plone27_reservations(id),
  deuda uuid references plone27_debts(id),
  creada timestamptz not null default now(),
  check(aprobada_por is null or aprobada_por<>propuesta_por),
  check(ejecutada_por is null or ejecutada_por<>propuesta_por),
  check(tipo='embargo' or destino is not null));

-- Proponer (solo la Junta). Multas e incautaciones necesitan cuenta de destino de administración.
create or replace function plone27_sancion_proponer(p_bank uuid,p_tipo text,p_iban text,p_importe numeric,p_motivo text,
    p_norma text,p_iban_destino text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c uuid; d uuid; sid uuid; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta puede proponer sanciones'; end if;
  if p_tipo not in('multa','incautacion','embargo') then raise exception 'Tipo no válido (multa, incautacion o embargo)'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'El importe debe ser mayor que cero'; end if;
  if coalesce(length(p_motivo),0)<20 then raise exception 'El motivo debe explicar el hecho (mínimo 20 caracteres)'; end if;
  if coalesce(length(p_norma),0)<5 then raise exception 'Indica la norma que respalda la sanción'; end if;
  select a.id into c from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if c is null then raise exception 'La cuenta no pertenece a tu entidad'; end if;
  if exists(select 1 from plone27_accounts a where a.id=c and a.kind in('joven','system')) then
    raise exception 'Esta cuenta no puede ser objeto de sanción (cuenta Placeta Joven o de administración)';
  end if;
  if p_tipo in('multa','incautacion') then
    select a.id into d from plone27_accounts a where a.iban=p_iban_destino and a.bank_id=p_bank and a.kind='system';
    if d is null then raise exception 'La cuenta de destino debe ser de administración de tu entidad'; end if;
  end if;
  insert into plone27_sanciones(bank_id,tipo,cuenta,destino,importe,motivo,norma,propuesta_por)
    values(p_bank,p_tipo,c,d,p_importe,p_motivo,p_norma,p_actor) returning plone27_sanciones.id into sid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_proponer','sancion',sid::text,jsonb_build_object('tipo',p_tipo,'importe',p_importe));
  return sid; end $$;

-- Aprobar: otra persona de la Junta
create or replace function plone27_sancion_aprobar(p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta puede aprobar sanciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'propuesta' then raise exception 'La sanción no está pendiente de aprobación'; end if;
  if s.propuesta_por=p_actor then raise exception 'Quien propone una sanción no puede aprobarla'; end if;
  update plone27_sanciones set estado='aprobada', aprobada_por=p_actor where id=p_id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_aprobar','sancion',p_id::text,'{}'::jsonb); end $$;

-- Notificar: abre el plazo para recurrir
create or replace function plone27_sancion_notificar(p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; dias int; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta puede notificar sanciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'aprobada' then raise exception 'La sanción debe estar aprobada para notificarla'; end if;
  dias:=(plone27_setting('sancion_plazo_recurso_dias')#>>'{}')::int;
  update plone27_sanciones set estado='notificada', notificada_at=now(), plazo_recurso_hasta=now()+(dias*interval '1 day') where id=p_id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_notificar','sancion',p_id::text,jsonb_build_object('plazo_dias',dias)); end $$;

-- Recurrir: mientras esté recurrida no se ejecuta
create or replace function plone27_sancion_recurrir(p_id uuid,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta registra recursos'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'El recurso debe explicar sus motivos (mínimo 10 caracteres)'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'notificada' then raise exception 'Solo se puede recurrir una sanción notificada'; end if;
  if now()>s.plazo_recurso_hasta then raise exception 'El plazo para recurrir ya ha terminado'; end if;
  update plone27_sanciones set estado='recurrida', recurso_motivo=p_motivo where id=p_id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_recurrir','sancion',p_id::text,jsonb_build_object('motivo',p_motivo)); end $$;

-- Resolver el recurso: otra persona de la Junta. Confirmar la sanción la deja firme; anularla la cancela.
create or replace function plone27_sancion_resolver_recurso(p_id uuid,p_confirmar boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta resuelve recursos'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'recurrida' then raise exception 'La sanción no tiene un recurso pendiente'; end if;
  if s.propuesta_por=p_actor then raise exception 'Quien propone la sanción no puede resolver su recurso'; end if;
  if p_confirmar then
    update plone27_sanciones set estado='firme', resolucion_recurso='confirmada' where id=p_id;
  else
    if s.reserva is not null then perform plone27_release(s.reserva,p_actor); end if;
    update plone27_sanciones set estado='anulada', resolucion_recurso='anulada' where id=p_id;
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_resolver_recurso','sancion',p_id::text,jsonb_build_object('confirmada',p_confirmar)); end $$;

-- Firme automática: notificada y sin recurso dentro de plazo (lo llama el proceso diario)
create or replace function plone27_sancion_firme_auto(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
declare n int; begin
  with x as(update plone27_sanciones set estado='firme' where estado='notificada' and plazo_recurso_hasta<now() returning 1)
  select count(*) into n from x;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_firme','sancion',null,jsonb_build_object('firmes',n));
  return n; end $$;

-- Ejecutar una sanción firme. Otra persona de la Junta distinta de quien la propuso.
create or replace function plone27_sancion_ejecutar(p_id uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; inemb numeric; disp numeric; maxi numeric; tx uuid; rid uuid; did uuid; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta ejecuta sanciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'firme' then raise exception 'La sanción no está firme'; end if;
  if s.propuesta_por=p_actor then raise exception 'Quien propone la sanción no puede ejecutarla'; end if;
  if s.tipo='multa' then
    insert into plone27_debts(account_id,principal,due_date,authorized_by,reason,creditor_account)
      values(s.cuenta,s.importe,current_date+15,p_actor,'Multa: '||s.motivo,s.destino) returning plone27_debts.id into did;
    update plone27_sanciones set estado='ejecutada', deuda=did, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
    return jsonb_build_object('tipo','multa','deuda',did);
  end if;
  inemb:=(plone27_setting('sancion_inembargable_pz')#>>'{}')::numeric;
  disp:=plone27_available(s.cuenta);
  maxi:=greatest(disp-inemb,0);
  if s.importe>maxi then
    raise exception 'Solo es embargable o incautable hasta % Pz: el resto es inembargable', maxi;
  end if;
  if s.tipo='incautacion' then
    tx:=plone27_transfer('sancion:'||s.id::text,s.cuenta,s.destino,s.importe,'Incautación: '||left(s.motivo,80),p_actor);
    update plone27_sanciones set estado='ejecutada', transaccion=tx, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
    return jsonb_build_object('tipo','incautacion','transaccion',tx);
  end if;
  rid:=plone27_reserve(s.cuenta,s.importe,'Embargo: '||left(s.motivo,80),p_actor);
  update plone27_sanciones set estado='ejecutada', reserva=rid, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
  return jsonb_build_object('tipo','embargo','reserva',rid); end $$;

-- Levantar un embargo ejecutado: libera el dinero y cierra la sanción
create or replace function plone27_sancion_levantar(p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta levanta embargos'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.tipo<>'embargo' or s.estado<>'ejecutada' then raise exception 'Solo se levanta un embargo ejecutado'; end if;
  if s.reserva is not null then perform plone27_release(s.reserva,p_actor); end if;
  update plone27_sanciones set estado='anulada' where id=p_id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_levantar','sancion',p_id::text,'{}'::jsonb); end $$;

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

do $$ begin raise notice 'Actualización 0072 aplicada correctamente.'; end $$;

commit;
