begin;
-- Placeta One · 0074 · Justicia: avisos para que cada banco notifique (Gmail propio), ejecuciones programadas
-- con 5 horas de antelación, recurso solo mediante denuncia, y revocación de sanciones con deshacer efectos.
-- Requiere 0073. Idempotente. NO ejecutado en PostgreSQL.

-- 1) Estados y columnas nuevas de sanciones
do $$ declare r record; begin
  for r in select c.conname from pg_constraint c join pg_class t on t.oid=c.conrelid
    where t.relname='plone27_sanciones' and c.contype='c' and pg_get_constraintdef(c.oid) like '%estado%' loop
    execute format('alter table plone27_sanciones drop constraint %I', r.conname);
  end loop;
end $$;
alter table plone27_sanciones add constraint plone27_sanciones_estado_check
  check(estado in('propuesta','aprobada','notificada','recurrida','firme','ejecutada','anulada','revocada'));
alter table plone27_sanciones add column if not exists ejecucion_prevista timestamptz;
alter table plone27_sanciones add column if not exists revocada_por uuid;
alter table plone27_sanciones add column if not exists revocada_at timestamptz;
alter table plone27_sanciones add column if not exists revocacion_motivo text;

-- 2) Denuncias: la única vía para recurrir
create table if not exists plone27_denuncias(
  id uuid primary key default gen_random_uuid(),
  sancion uuid not null references plone27_sanciones(id),
  dip text not null,
  texto text not null check(length(texto)>=20),
  presentada timestamptz not null default now());

-- 3) Avisos que cada banco convierte en correos con su propio Gmail
create table if not exists plone27_avisos(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks(id),
  cuenta uuid not null references plone27_accounts(id),
  tipo text not null check(tipo in('sancion_notificada','ejecucion_prevista','cobro_multa_previsto','sancion_revocada')),
  sancion uuid references plone27_sanciones(id),
  mensaje text not null,
  ejecuta_en timestamptz,
  visible_desde timestamptz not null,
  estado text not null default 'pendiente' check(estado in('pendiente','entregado')),
  entregado_at timestamptz,
  creado timestamptz not null default now());

-- Recurrir ya no existe: solo denunciando
drop function if exists plone27_sancion_recurrir(uuid,text,uuid);

-- Notificar: abre el plazo y avisa al banco
create or replace function plone27_sancion_notificar(p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; dias int; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta puede notificar sanciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'aprobada' then raise exception 'La sanción debe estar aprobada para notificarla'; end if;
  dias:=(plone27_setting('sancion_plazo_recurso_dias')#>>'{}')::int;
  update plone27_sanciones set estado='notificada', notificada_at=now(), plazo_recurso_hasta=now()+(dias*interval '1 day') where id=p_id;
  insert into plone27_avisos(bank_id,cuenta,tipo,sancion,mensaje,ejecuta_en,visible_desde)
    values(s.bank_id,s.cuenta,'sancion_notificada',p_id,
      'Se ha notificado una sanción sobre tu cuenta. Para recurrirla debes presentar denuncia ante justicia antes del '||
      (now()+(dias*interval '1 day'))::date::text||'.',now()+(dias*interval '1 day'),now());
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_notificar','sancion',p_id::text,jsonb_build_object('plazo_dias',dias)); end $$;

-- Denunciar: la persona sancionada (o su tutor) presenta denuncia a través de su banco. Abre el recurso.
create or replace function plone27_sancion_denunciar(p_bank uuid,p_sancion uuid,p_dip text,p_texto text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; did uuid; d text; begin
  select * into s from plone27_sanciones where id=p_sancion for update;
  if s.id is null or s.bank_id<>p_bank then raise exception 'Sanción no encontrada en tu entidad'; end if;
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
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_denuncia','sancion',p_sancion::text,jsonb_build_object('denuncia',did));
  return did; end $$;

-- Programar la ejecución: con al menos 5 horas de antelación; genera el aviso 5 horas antes
create or replace function plone27_sancion_programar(p_id uuid,p_fecha timestamptz,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta programa ejecuciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'firme' then raise exception 'Solo se programa una sanción firme'; end if;
  if p_fecha < now()+interval '5 hours' then raise exception 'La ejecución debe programarse con al menos 5 horas de antelación'; end if;
  update plone27_sanciones set ejecucion_prevista=p_fecha where id=p_id;
  insert into plone27_avisos(bank_id,cuenta,tipo,sancion,mensaje,ejecuta_en,visible_desde)
    values(s.bank_id,s.cuenta,'ejecucion_prevista',p_id,
      'Está prevista una '||case s.tipo when 'multa' then 'multa' when 'incautacion' then 'incautación' else 'embargo' end||
      ' sobre tu cuenta el '||to_char(p_fecha,'DD/MM/YYYY HH24:MI')||' (UTC).',p_fecha,p_fecha-interval '5 hours');
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_programar','sancion',p_id::text,jsonb_build_object('fecha',p_fecha));
end $$;

-- Ejecutar: la Junta, o el proceso diario (p_actor null) cuando llega la hora programada
create or replace function plone27_sancion_ejecutar(p_id uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; k text; inemb numeric; disp numeric; maxi numeric; tx uuid; rid uuid; did uuid; cobro timestamptz; begin
  if p_actor is not null and not plone27_es_admin(p_actor) then raise exception 'Solo la Junta ejecuta sanciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'firme' then raise exception 'La sanción no está firme'; end if;
  if s.ejecucion_prevista is null or s.ejecucion_prevista>now() then raise exception 'La ejecución no está programada o aún no ha llegado su hora'; end if;
  select a.kind into k from plone27_accounts a where a.id=s.cuenta;
  perform set_config('plone27.sancion','on',true);
  if k='joven' then perform set_config('plone27.joven_op','on',true); end if;
  inemb:=(plone27_setting('sancion_inembargable_pz')#>>'{}')::numeric;
  disp:=plone27_available(s.cuenta);
  maxi:=greatest(disp-inemb,0);
  if s.tipo='multa' and k<>'joven' then
    insert into plone27_debts(account_id,principal,due_date,authorized_by,reason,creditor_account)
      values(s.cuenta,s.importe,current_date+15,p_actor,'Multa: '||s.motivo,s.destino) returning plone27_debts.id into did;
    cobro:=((current_date+15)::timestamp+interval '4 hours') at time zone 'UTC';
    insert into plone27_avisos(bank_id,cuenta,tipo,sancion,mensaje,ejecuta_en,visible_desde)
      values(s.bank_id,s.cuenta,'cobro_multa_previsto',p_id,'Se cobrará la multa el '||to_char(cobro,'DD/MM/YYYY')||' si no tienes saldo antes.',cobro,cobro-interval '5 hours');
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

-- Ejecutar todas las sanciones cuya hora programada ya ha llegado (lo llama el proceso diario)
create or replace function plone27_sanciones_ejecutar_vencidas(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
declare r record; n int:=0; begin
  for r in select id from plone27_sanciones where estado='firme' and ejecucion_prevista is not null and ejecucion_prevista<=now() order by ejecucion_prevista loop
    begin
      perform plone27_sancion_ejecutar(r.id,null);
      n:=n+1;
    exception when others then
      insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(null,'sancion_error','sancion',r.id::text,jsonb_build_object('error',sqlerrm));
    end;
  end loop;
  return n; end $$;

-- Revocar: anula la sanción y deshace sus efectos (devuelve el dinero, libera el embargo o anula una multa sin pagos)
create or replace function plone27_sancion_revocar(p_id uuid,p_motivo text,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; k text; efectos boolean:=false; begin
  if not plone27_es_admin(p_actor) then raise exception 'Solo la Junta revoca sanciones'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'El motivo de la revocación debe tener al menos 10 caracteres'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado not in('notificada','recurrida','firme','ejecutada') then raise exception 'Esta sanción no se puede revocar en su estado actual'; end if;
  select a.kind into k from plone27_accounts a where a.id=s.cuenta;
  perform set_config('plone27.sancion','on',true);
  if k='joven' then perform set_config('plone27.joven_op','on',true); end if;
  if s.estado='ejecutada' then
    efectos:=true;
    if s.tipo='embargo' then
      if s.reserva is not null then perform plone27_release(s.reserva,p_actor); end if;
    elsif s.transaccion is not null then
      perform plone27_reverse('rev-sancion:'||s.id::text,s.transaccion,p_motivo,p_actor);
    elsif s.deuda is not null then
      if exists(select 1 from plone27_debts where id=s.deuda and paid>0) then
        raise exception 'La multa ya tiene pagos: revierte los pagos antes de revocarla';
      end if;
      update plone27_debts set disputed=true where id=s.deuda;
    end if;
  end if;
  update plone27_sanciones set estado='revocada', revocada_por=p_actor, revocada_at=now(), revocacion_motivo=p_motivo where id=p_id;
  insert into plone27_avisos(bank_id,cuenta,tipo,sancion,mensaje,ejecuta_en,visible_desde)
    values(s.bank_id,s.cuenta,'sancion_revocada',p_id,'La sanción sobre tu cuenta ha sido revocada.',now(),now());
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'sancion_revocar','sancion',p_id::text,jsonb_build_object('motivo',p_motivo,'efectos_revertidos',efectos));
  return jsonb_build_object('revocada',true,'efectos_revertidos',efectos); end $$;

-- Avisos pendientes de un banco: solo los que ya son visibles
create or replace function plone27_avisos_pendientes(p_bank uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.visible_desde) from (
    select v.id, v.tipo, a.iban, v.mensaje, v.ejecuta_en, v.visible_desde, v.sancion
    from plone27_avisos v join plone27_accounts a on a.id=v.cuenta
    where v.bank_id=p_bank and v.estado='pendiente' and v.visible_desde<=now()
  ) x), '[]'::jsonb); end $$;

-- Acuse de recibo del banco: ya lo ha enviado por su cuenta
create or replace function plone27_aviso_acusar(p_bank uuid,p_aviso uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  update plone27_avisos set estado='entregado', entregado_at=now() where id=p_aviso and bank_id=p_bank and estado='pendiente';
  if not found then raise exception 'Aviso no encontrado o ya entregado'; end if; end $$;

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

do $$ begin raise notice 'Actualización 0074 aplicada correctamente.'; end $$;

commit;
