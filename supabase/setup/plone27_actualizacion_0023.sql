-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0023 · Pasarela para webs de bancos y pagos por API
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0022.
-- AÑADE: logo y color por banco, pasarela con código de verificación, cargos de tarjeta con idempotencia,
--        y lectura de nóminas y planes por entidad.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0023 · Pasarela de pago para webs de bancos (popup con código de verificación),
-- cargos de tarjeta por API con idempotencia, y lectura de nóminas y planes por entidad.
-- Requiere 0022. Idempotente.

-- ---------- Identidad visual de cada banco ----------
alter table plone27_banks add column if not exists logo_url text check(logo_url is null or logo_url ~ '^https://[^\s]+$');
alter table plone27_banks add column if not exists color_principal text check(color_principal is null or color_principal ~ '^#[0-9A-Fa-f]{6}$');

-- ---------- Cargos de tarjeta: clave de idempotencia ----------
alter table plone27_card_charges add column if not exists idem_key text unique;

-- ---------- Hash de tokens y códigos (nunca se guardan en claro) ----------
create or replace function plone27_sha(p text) returns text language sql immutable as $$
  select encode(sha256(convert_to(p,'utf8')),'hex') $$;

-- ---------- Pagos de pasarela ----------
create table if not exists plone27_checkouts(
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  bank_id uuid not null references plone27_banks,
  client_id uuid not null references plone27_api_clients,
  origen_banco text not null check(origen_banco ~ '^https://[^\s]+$' or origen_banco ~ '^http://localhost(:[0-9]+)?$'),
  client_ref text not null check(length(client_ref) between 1 and 80),
  pagador_persona uuid not null references plone27_personas,
  pagador_cuenta uuid not null references plone27_accounts,
  cuenta_destino uuid not null references plone27_accounts,
  importe numeric(18,2) not null check(importe>0),
  concepto text not null check(length(concepto) between 1 and 120),
  codigo_hash text not null,
  codigo_expira timestamptz not null,
  intentos int not null default 0 check(intentos between 0 and 10),
  estado text not null default 'pendiente' check(estado in('pendiente','pagado','fallido','cancelado','caducado')),
  tx uuid,
  expira_at timestamptz not null,
  creada timestamptz not null default now(),
  resuelta timestamptz,
  unique(client_id,client_ref));

-- Crea un pago. El código de verificación sale por webhook (checkout.codigo) hacia el banco.
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; cuenta uuid; destino uuid; cid uuid; caduca timestamptz; mins int := coalesce(p_minutos,15); begin
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>50000 then raise exception 'Importe entre 0,01 y 50.000 Pz'; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if coalesce(length(p_codigo),0)<>6 then raise exception 'Código de verificación no válido'; end if;
  pid := plone27_persona(p_dip);
  select a.id into cuenta from plone27_accounts a where a.iban=p_iban_pagador and a.bank_id=p_bank;
  if cuenta is null or not plone27_user_can(pid,cuenta,true,p_bank) then raise exception 'Cuenta del pagador no accesible'; end if;
  select a.id into destino from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  caduca := now()+make_interval(mins => mins);
  insert into plone27_checkouts(token_hash,bank_id,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
                                importe,concepto,codigo_hash,codigo_expira,expira_at)
    values(plone27_sha(p_token),p_bank,p_client,lower(p_origen),p_client_ref,pid,cuenta,destino,
           p_importe,p_concepto,plone27_sha(p_codigo),caduca,caduca)
    returning id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.codigo',array[p_bank],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'codigo',p_codigo,'importe',p_importe,'concepto',p_concepto,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca);
end $$;

-- Estado público del pago para la ventana emergente (sin datos internos)
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'intentos_restantes',greatest(0,3-c.intentos),
    'origen',c.origen_banco,'banco',jsonb_build_object('nombre',b.name,'logo',b.logo_url,'color',b.color_principal),
    'comercio',cl.name)
  from plone27_checkouts c join plone27_banks b on b.id=c.bank_id join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

-- Confirmación con el código. Tres intentos. La transferencia es idempotente por el id del pago.
create or replace function plone27_checkout_confirm(p_token text,p_codigo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; tx uuid; begin
  select * into c from plone27_checkouts where token_hash=plone27_sha(p_token) for update;
  if c.id is null then return jsonb_build_object('ok',false,'error','Pago no encontrado'); end if;
  if c.estado<>'pendiente' then return jsonb_build_object('ok',false,'error','Este pago ya no está pendiente','estado',c.estado); end if;
  if c.expira_at<now() then
    update plone27_checkouts set estado='caducado',resuelta=now() where id=c.id;
    return jsonb_build_object('ok',false,'error','El pago ha caducado','estado','caducado');
  end if;
  if c.codigo_hash<>plone27_sha(coalesce(p_codigo,'')) then
    update plone27_checkouts set intentos=intentos+1,
      estado=case when intentos+1>=3 then 'fallido' else estado end,
      resuelta=case when intentos+1>=3 then now() else resuelta end
      where id=c.id;
    return jsonb_build_object('ok',false,'error','Código incorrecto',
      'intentos_restantes',greatest(0,2-c.intentos),
      'estado',case when c.intentos+1>=3 then 'fallido' else 'pendiente' end);
  end if;
  begin
    tx:=plone27_transfer('checkout:'||c.id::text,c.pagador_cuenta,c.cuenta_destino,c.importe,c.concepto,null);
  exception when others then
    return jsonb_build_object('ok',false,'error',sqlerrm,'estado','pendiente');
  end;
  update plone27_checkouts set estado='pagado',tx=tx,resuelta=now() where id=c.id;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.pagado',array[c.bank_id],
    jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'importe',c.importe,'transaccion',tx));
  return jsonb_build_object('ok',true,'transaccion',tx,'estado','pagado');
end $$;

create or replace function plone27_checkout_cancel(p_token text) returns boolean
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_checkouts set estado='cancelado',resuelta=now()
            where token_hash=plone27_sha(p_token) and estado='pendiente' returning 1)
  select count(*) into n from x;
  if n>0 then
    insert into plone27_outbox(event,bank_ids,payload)
      select 'checkout.cancelado',array[c.bank_id],jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref)
      from plone27_checkouts c where c.token_hash=plone27_sha(p_token);
  end if;
  return n>0; end $$;

-- Consulta del banco: sin código, sin token
create or replace function plone27_bk_checkout_get(p_client uuid,p_id uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',c.id,'client_ref',c.client_ref,
    'estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'transaccion',c.tx,'creado',c.creada,'resuelto',c.resuelta,'intentos',c.intentos)
  from plone27_checkouts c where c.id=p_id and c.client_id=p_client $$;

-- ---------- Tarjetas por API (el banco solo opera sobre sus tarjetas) ----------
create or replace function plone27_bk_card_authorize(p_bank uuid,p_card_ref text,p_importe numeric,p_iban_comercio text,p_key text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; m uuid; ch uuid; st text; begin
  if coalesce(length(p_key),0)=0 then raise exception 'Idempotency-Key obligatoria'; end if;
  if p_importe is null or p_importe<=0 then raise exception 'Importe no válido'; end if;
  select cd.* into c from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
    where cd.card_ref=p_card_ref and a.bank_id=p_bank;
  if c.id is null then raise exception 'Tarjeta no encontrada'; end if;
  select cg.id into ch from plone27_card_charges cg where cg.idem_key=p_key;
  if ch is not null then
    select cg.status into st from plone27_card_charges cg where cg.id=ch;
    return jsonb_build_object('cargo',ch,'estado',st);
  end if;
  select a.id into m from plone27_accounts a where a.iban=p_iban_comercio and a.status='active';
  if m is null then raise exception 'Cuenta del comercio no válida'; end if;
  ch:=plone27_card_authorize(c.id,p_importe,m,null);
  update plone27_card_charges set idem_key=p_key where id=ch;
  select cg.status into st from plone27_card_charges cg where cg.id=ch;
  return jsonb_build_object('cargo',ch,'estado',st);
end $$;

create or replace function plone27_bk_card_settle(p_bank uuid,p_charge uuid,p_key text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ok boolean; tx uuid; st text; begin
  select exists(select 1 from plone27_card_charges cg join plone27_cards cd on cd.id=cg.card_id
                join plone27_accounts a on a.id=cd.account_id where cg.id=p_charge and a.bank_id=p_bank) into ok;
  if not ok then raise exception 'Cargo no encontrado'; end if;
  tx:=plone27_card_settle(p_key,p_charge,null);
  select cg.status into st from plone27_card_charges cg where cg.id=p_charge;
  return jsonb_build_object('transaccion',tx,'estado',st);
end $$;

create or replace function plone27_bk_card_release(p_bank uuid,p_charge uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cg plone27_card_charges; begin
  select cg.* into cg from plone27_card_charges cg join plone27_cards cd on cd.id=cg.card_id
    join plone27_accounts a on a.id=cd.account_id
    where cg.id=p_charge and a.bank_id=p_bank for update of cg;
  if cg.id is null then raise exception 'Cargo no encontrado'; end if;
  if cg.status<>'authorized' then raise exception 'Solo se liberan cargos autorizados'; end if;
  if cg.reservation_id is not null then perform plone27_release(cg.reservation_id,null); end if;
  update plone27_card_charges set status='released' where id=p_charge;
  return jsonb_build_object('estado','released');
end $$;

-- ---------- Lectura de nóminas y planes por entidad ----------
create or replace function plone27_bk_nominas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.proximo_pago),'[]'::jsonb) from (
    select c.id, c.gross_monthly as bruto, c.pay_day as dia_pago, c.next_pay as proximo_pago, c.status as estado,
           c.full_time as jornada_completa, c.start_date as inicio
    from plone27_contracts c where c.bank_id=p_bank) x $$;

create or replace function plone27_bk_planes(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.proximo),'[]'::jsonb) from (
    select p.id, p.kind as tipo, p.principal, p.installments as cuotas, p.status as estado, p.next_due as proximo,
           (select count(*) from plone27_plan_items i where i.plan_id=p.id and i.status='pending') as cuotas_pendientes
    from plone27_plans p where p.bank_id=p_bank) x $$;

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


do $$ begin raise notice 'Actualización 0023 aplicada correctamente.'; end $$;

commit;
