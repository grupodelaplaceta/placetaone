-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0040 · Liquidación interbancaria, límites, reversión y tasas (TODO APAGADO)
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0039.
-- ATENCIÓN: esta migración no se ha ejecutado en PostgreSQL. Probar en una base de pruebas antes de producción.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0040 · Liquidación interbancaria neta diaria, límite de exposición, reversión con doble aprobación
-- y motor de tasas para transferencias interbancarias y cargos de tarjeta de empresa.
-- Todo empieza DESACTIVADO (plone27_config_interbancaria). Requiere 0039. Idempotente.

-- ---------- Interruptores ----------
create table if not exists plone27_config_interbancaria(
  id int primary key default 1 check(id=1),
  liquidacion_activa boolean not null default false,
  tasas_operaciones_activas boolean not null default false,
  actualizada timestamptz not null default now());
insert into plone27_config_interbancaria(id) values(1) on conflict(id) do nothing;

-- ---------- Liquidaciones, operaciones pendientes de liquidar y límites ----------
create table if not exists plone27_liquidaciones(
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  banco_deudor uuid not null references plone27_banks,
  banco_acreedor uuid not null references plone27_banks,
  importe numeric(18,2) not null check(importe>0),
  estado text not null check(estado in('pendiente','ejecutada','revertida','compensatoria')),
  motivo text check(motivo is null or length(motivo)>=10),
  revierte uuid references plone27_liquidaciones(id),
  tx uuid,
  aprobada_por uuid,
  aprobada_por2 uuid,
  creada timestamptz not null default now(),
  check(banco_deudor<>banco_acreedor));

create table if not exists plone27_operaciones_interbancarias(
  id bigint generated always as identity primary key,
  origen uuid not null references plone27_banks,
  destino uuid not null references plone27_banks,
  importe numeric(18,2) not null check(importe>0),
  ref text not null unique,
  fecha date not null default current_date,
  liquidada_en uuid references plone27_liquidaciones(id),
  check(origen<>destino));

create table if not exists plone27_limites_exposicion(
  bank_deudor uuid not null references plone27_banks,
  bank_acreedor uuid not null references plone27_banks,
  limite numeric(18,2) not null check(limite>=0),
  primary key(bank_deudor,bank_acreedor),
  check(bank_deudor<>bank_acreedor));

create table if not exists plone27_reversiones(
  id uuid primary key default gen_random_uuid(),
  liquidacion uuid not null references plone27_liquidaciones(id),
  motivo text not null check(length(motivo)>=10),
  solicitada_por uuid not null,
  aprobada_por uuid,
  estado text not null default 'pendiente' check(estado in('pendiente','ejecutada','rechazada')),
  creada timestamptz not null default now(),
  resuelta timestamptz);
create unique index if not exists plone27_reversion_pendiente_ux on plone27_reversiones(liquidacion) where estado='pendiente';

-- ---------- Tasas: nuevas operaciones (la tasa la paga siempre el banco emisor) ----------
alter table plone27_tasas drop constraint if exists plone27_tasas_operacion_check;
do $$ begin alter table plone27_tasas add constraint plone27_tasas_operacion_check
  check(operacion in('pasarela_pago','transferencia_interbancaria','cargo_tarjeta_empresa')) not valid; exception when duplicate_object then null; end $$;

create or replace function plone27_tasas_operacion(p_bank uuid,p_operacion text,p_medio text,p_importe numeric)
returns table(tasa uuid,beneficiario text,monto numeric)
language sql stable security definer set search_path=public as $$
  select t.id, t.beneficiario,
    round(least(greatest(case when t.tipo='fijo' then t.valor else p_importe*t.valor/100 end, t.minimo),
      coalesce(t.maximo,999999999999)),2)
  from plone27_tasas t
  where t.activa and t.bank_id=p_bank and t.operacion=p_operacion and t.client_id is null
    and (t.medio is null or t.medio=p_medio) $$;

create or replace function plone27_tasa_alta_operacion(p_bank uuid,p_operacion text,p_tipo text,p_valor numeric,p_minimo numeric,p_maximo numeric,
    p_beneficiario text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare tid uuid; begin
  if p_operacion not in('transferencia_interbancaria','cargo_tarjeta_empresa') then raise exception 'Operación no válida'; end if;
  if not exists(select 1 from plone27_banks b where b.id=p_bank) then raise exception 'Entidad no encontrada'; end if;
  insert into plone27_tasas(ambito,bank_id,operacion,tipo,valor,minimo,maximo,pagador,beneficiario)
    values('propietario',p_bank,p_operacion,p_tipo,p_valor,coalesce(p_minimo,0),p_maximo,'banco',p_beneficiario)
    returning plone27_tasas.id into tid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'tasa_operacion_alta','bank',p_bank::text,jsonb_build_object('operacion',p_operacion,'valor',p_valor,'tipo',p_tipo));
  return tid; end $$;

-- Cobra las tasas de una operación interbancaria. Misma entidad: exenta. Cargos de tarjeta: solo cuentas de empresa.
-- Con el interruptor apagado no hace nada y devuelve 0.
create or replace function plone27_cobrar_tasa(p_operacion text,p_cuenta_origen uuid,p_cuenta_destino uuid,p_importe numeric,p_key text,p_actor uuid)
returns numeric
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ob uuid; db uuid; okind text; t record; total numeric:=0; orig uuid; ben uuid; begin
  if not coalesce((select c.tasas_operaciones_activas from plone27_config_interbancaria c where c.id=1),false) then return 0; end if;
  select a.bank_id, a.kind into ob, okind from plone27_accounts a where a.id=p_cuenta_origen;
  select a.bank_id into db from plone27_accounts a where a.id=p_cuenta_destino;
  if ob is null or db is null or ob=db then return 0; end if;
  if p_operacion='cargo_tarjeta_empresa' and okind<>'business' then return 0; end if;
  for t in select x.tasa, x.beneficiario, x.monto from plone27_tasas_operacion(ob,p_operacion,null,p_importe) x loop
    if t.monto<=0 then continue; end if;
    orig:=plone27_comision_cuenta(ob);
    ben:=case when t.beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(ob) end;
    if orig=ben then continue; end if;
    perform plone27_transfer('tasa-op:'||p_key||':'||t.tasa::text,orig,ben,t.monto,'Tasa interbancaria',p_actor);
    total:=total+t.monto;
  end loop;
  return total; end $$;

-- ---------- Registro de operaciones interbancarias pagadas ----------
create or replace function plone27_registrar_op(p_origen uuid,p_destino uuid,p_importe numeric,p_ref text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_origen is null or p_destino is null or p_origen=p_destino then return; end if;
  insert into plone27_operaciones_interbancarias(origen,destino,importe,ref) values(p_origen,p_destino,p_importe,p_ref)
    on conflict(ref) do nothing;
end $$;

create or replace function plone27_trg_ops_checkout() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare dest uuid; begin
  if not new.interbancaria then return new; end if;
  select a.bank_id into dest from plone27_accounts a where a.id=new.cuenta_destino;
  perform plone27_registrar_op(new.banco_pagador,dest,new.importe,'checkout:'||new.id::text);
  return new; end $$;
drop trigger if exists trg_ops_checkout on plone27_checkouts;
drop trigger if exists trg_ops_checkout on plone27_checkouts;
create trigger trg_ops_checkout after update of estado on plone27_checkouts
  for each row when (new.estado='pagado' and old.estado is distinct from 'pagado')
  execute function plone27_trg_ops_checkout();

-- ---------- Límite de exposición: se comprueba antes de crear un pago interbancario ----------
create or replace function plone27_trg_limite_exposicion() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare dest uuid; lim numeric; neto numeric; begin
  if not new.interbancaria then return new; end if;
  select a.bank_id into dest from plone27_accounts a where a.id=new.cuenta_destino;
  select l.limite into lim from plone27_limites_exposicion l where l.bank_deudor=new.banco_pagador and l.bank_acreedor=dest;
  if lim is null then return new; end if;
  select coalesce(sum(case when o.origen=new.banco_pagador then o.importe else -o.importe end),0) into neto
    from plone27_operaciones_interbancarias o
    where o.liquidada_en is null and ((o.origen=new.banco_pagador and o.destino=dest) or (o.origen=dest and o.destino=new.banco_pagador));
  neto:=neto+coalesce((select sum(c.importe) from plone27_checkouts c join plone27_accounts a on a.id=c.cuenta_destino
    where c.estado='pendiente' and c.interbancaria and c.banco_pagador=new.banco_pagador and a.bank_id=dest and c.expira_at>now()),0);
  if neto+new.importe>lim then
    raise exception 'Tu entidad ha alcanzado su límite de exposición con ese banco: hay que liquidar antes de nuevos pagos interbancarios';
  end if;
  return new; end $$;
drop trigger if exists trg_limite_exposicion on plone27_checkouts;
drop trigger if exists trg_limite_exposicion on plone27_checkouts;
create trigger trg_limite_exposicion before insert on plone27_checkouts
  for each row execute function plone27_trg_limite_exposicion();

-- ---------- Cuenta de liquidación de cada banco (la financia el propio banco) ----------
create or replace function plone27_cuenta_liquidacion(p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  select a.id into cid from plone27_accounts a where a.bank_id=p_bank and a.kind='system' and a.name='Liquidación interbancaria' limit 1;
  if cid is null then cid:=(plone27_open_account(p_bank,'system','Liquidación interbancaria',null,null)->>'id')::uuid; end if;
  return cid; end $$;

create or replace function plone27_limite_set(p_deudor uuid,p_acreedor uuid,p_limite numeric,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_deudor=p_acreedor then raise exception 'Un banco no tiene límite frente a sí mismo'; end if;
  insert into plone27_limites_exposicion(bank_deudor,bank_acreedor,limite) values(p_deudor,p_acreedor,p_limite)
    on conflict(bank_deudor,bank_acreedor) do update set limite=excluded.limite;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'limite_exposicion','bank',p_deudor::text,jsonb_build_object('acreedor',p_acreedor,'limite',p_limite));
end $$;

-- ---------- Liquidación neta: todo o nada ----------
create or replace function plone27_liquidar(p_fecha date,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v_liq boolean; r record; v_a uuid; v_b uuid; v_neto numeric; v_deudor uuid; v_acreedor uuid; v_monto numeric;
  v_ca uuid; v_cb uuid; v_id uuid; v_tx uuid; v_n int:=0; v_code text; begin
  perform pg_advisory_xact_lock(hashtext('plone27_liquidacion'));
  select c.liquidacion_activa into v_liq from plone27_config_interbancaria c where c.id=1;
  if not coalesce(v_liq,false) then raise exception 'La liquidación interbancaria está desactivada'; end if;
  for r in select distinct least(o.origen,o.destino) as ba, greatest(o.origen,o.destino) as bb
           from plone27_operaciones_interbancarias o where o.liquidada_en is null and o.fecha<=p_fecha loop
    v_a:=r.ba; v_b:=r.bb;
    select coalesce(sum(case when o.origen=v_a then o.importe else -o.importe end),0) into v_neto
      from plone27_operaciones_interbancarias o
      where o.liquidada_en is null and o.fecha<=p_fecha and ((o.origen=v_a and o.destino=v_b) or (o.origen=v_b and o.destino=v_a));
    if v_neto=0 then continue; end if;
    if v_neto>0 then v_deudor:=v_a; v_acreedor:=v_b; else v_deudor:=v_b; v_acreedor:=v_a; end if;
    v_monto:=abs(v_neto);
    v_ca:=plone27_cuenta_liquidacion(v_deudor); v_cb:=plone27_cuenta_liquidacion(v_acreedor);
    if plone27_available(v_ca)<v_monto then
      select b.code into v_code from plone27_banks b where b.id=v_deudor;
      raise exception 'El banco % no tiene saldo en su cuenta de liquidación para pagar % Pz', v_code, v_monto;
    end if;
    insert into plone27_liquidaciones(fecha,banco_deudor,banco_acreedor,importe,estado)
      values(p_fecha,v_deudor,v_acreedor,v_monto,'pendiente') returning plone27_liquidaciones.id into v_id;
    v_tx:=plone27_transfer('liq:'||v_id::text,v_ca,v_cb,v_monto,'Liquidación interbancaria',p_actor);
    update plone27_liquidaciones set estado='ejecutada', tx=v_tx where id=v_id;
    update plone27_operaciones_interbancarias o set liquidada_en=v_id
      where o.liquidada_en is null and o.fecha<=p_fecha and ((o.origen=v_a and o.destino=v_b) or (o.origen=v_b and o.destino=v_a));
    v_n:=v_n+1;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'liquidacion_ejecutada','liquidacion',null,jsonb_build_object('fecha',p_fecha,'n',v_n));
  return jsonb_build_object('fecha',p_fecha,'liquidaciones',v_n); end $$;

-- ---------- Reversión: compensatoria, con dos personas distintas; reabre las operaciones para volver a liquidarlas ----------
create or replace function plone27_revertir_liquidacion(p_liq uuid,p_motivo text,p_solicitante uuid,p_aprobador uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare o plone27_liquidaciones; v_id uuid; v_ca uuid; v_cb uuid; v_tx uuid; begin
  if p_solicitante is null or p_aprobador is null or p_solicitante=p_aprobador then raise exception 'La reversión necesita dos personas distintas'; end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'El motivo debe tener al menos 10 caracteres'; end if;
  select * into o from plone27_liquidaciones where id=p_liq for update;
  if o.id is null or o.estado<>'ejecutada' then raise exception 'Solo se revierten liquidaciones ejecutadas'; end if;
  insert into plone27_liquidaciones(fecha,banco_deudor,banco_acreedor,importe,estado,motivo,revierte,aprobada_por,aprobada_por2)
    values(current_date,o.banco_acreedor,o.banco_deudor,o.importe,'compensatoria',p_motivo,o.id,p_solicitante,p_aprobador)
    returning plone27_liquidaciones.id into v_id;
  v_ca:=plone27_cuenta_liquidacion(o.banco_acreedor); v_cb:=plone27_cuenta_liquidacion(o.banco_deudor);
  if plone27_available(v_ca)<o.importe then raise exception 'La entidad acreedora no tiene saldo para devolver la liquidación'; end if;
  v_tx:=plone27_transfer('rev:'||v_id::text,v_ca,v_cb,o.importe,'Reversión de liquidación',p_aprobador);
  update plone27_liquidaciones set estado='ejecutada', tx=v_tx where id=v_id;
  update plone27_liquidaciones set estado='revertida' where id=o.id;
  update plone27_operaciones_interbancarias set liquidada_en=null where liquidada_en=o.id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_aprobador,'liquidacion_revertida','liquidacion',o.id::text,jsonb_build_object('compensatoria',v_id,'motivo',p_motivo));
  return v_id; end $$;

create or replace function plone27_reversion_solicitar(p_liq uuid,p_motivo text,p_solicitante uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rid uuid; begin
  if not exists(select 1 from plone27_liquidaciones l where l.id=p_liq and l.estado='ejecutada') then
    raise exception 'Solo se puede pedir la reversión de una liquidación ejecutada';
  end if;
  insert into plone27_reversiones(liquidacion,motivo,solicitada_por) values(p_liq,p_motivo,p_solicitante)
    returning plone27_reversiones.id into rid;
  return rid; end $$;

create or replace function plone27_reversion_aprobar(p_id uuid,p_aprobador uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rv plone27_reversiones; v uuid; begin
  select * into rv from plone27_reversiones r where r.id=p_id and r.estado='pendiente' for update;
  if rv.id is null then raise exception 'Solicitud de reversión no encontrada o ya resuelta'; end if;
  if rv.solicitada_por=p_aprobador then raise exception 'Quien solicita la reversión no puede aprobarla'; end if;
  v:=plone27_revertir_liquidacion(rv.liquidacion,rv.motivo,rv.solicitada_por,p_aprobador);
  update plone27_reversiones set estado='ejecutada', aprobada_por=p_aprobador, resuelta=now() where id=p_id;
  return v; end $$;

-- ---------- Interruptores ----------
create or replace function plone27_config_interbancaria_set(p_liquidacion boolean,p_tasas boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  update plone27_config_interbancaria set liquidacion_activa=coalesce(p_liquidacion,false),
    tasas_operaciones_activas=coalesce(p_tasas,false), actualizada=now() where id=1;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'config_interbancaria','config',null,jsonb_build_object('liquidacion',p_liquidacion,'tasas',p_tasas));
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


do $$ begin raise notice 'Actualización 0040 aplicada correctamente (liquidación y tasas desactivadas).'; end $$;

commit;
