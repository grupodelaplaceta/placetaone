-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0034 · APIs de banco: producto pasarela, branding, webhooks, cuentas y pagos
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0033.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0034 · APIs de banco: producto pasarela con parámetros, branding, webhooks, cuentas y listado de pagos.
-- Requiere 0033. Idempotente.

-- ---------- Producto pasarela por banco ----------
create table if not exists plone27_pasarela_config(
  bank_id uuid primary key references plone27_banks,
  activa boolean not null default false,
  minutos_defecto int not null default 15 check(minutos_defecto between 3 and 30),
  importe_maximo numeric(18,2) not null default 50000 check(importe_maximo>0),
  destinos text[] not null default '{business,system}',
  actualizada timestamptz not null default now());

-- ---------- Branding ----------
alter table plone27_banks add column if not exists nombre_visible text check(nombre_visible is null or length(nombre_visible) between 2 and 80);
alter table plone27_banks add column if not exists texto_pie text check(texto_pie is null or length(texto_pie)<=200);
alter table plone27_api_clients add column if not exists logo_url text check(logo_url is null or logo_url ~ '^https://[^\s]+$');
alter table plone27_api_clients add column if not exists color_principal text check(color_principal is null or color_principal ~ '^#[0-9A-Fa-f]{6}$');
alter table plone27_api_clients add column if not exists nombre_comercial text check(nombre_comercial is null or length(nombre_comercial) between 2 and 80);

create or replace function plone27_bk_pasarela_set(p_bank uuid,p_activa boolean,p_minutos int,p_importe_max numeric,p_destinos text[]) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if p_destinos is null or array_length(p_destinos,1) is null or not(p_destinos <@ array['business','system']::text[]) then
    raise exception 'Destinos no válidos (business, system)';
  end if;
  insert into plone27_pasarela_config(bank_id,activa,minutos_defecto,importe_maximo,destinos)
    values(p_bank,coalesce(p_activa,false),coalesce(p_minutos,15),coalesce(p_importe_max,50000),p_destinos)
    on conflict(bank_id) do update set activa=excluded.activa, minutos_defecto=excluded.minutos_defecto,
      importe_maximo=excluded.importe_maximo, destinos=excluded.destinos, actualizada=now();
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'pasarela_config','bank',p_bank::text,jsonb_build_object('activa',p_activa,'importe_maximo',p_importe_max,'destinos',p_destinos));
end $$;

-- ---------- Branding ----------
create or replace function plone27_bk_branding_set(p_bank uuid,p_logo text,p_color text,p_nombre text,p_texto text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_banks set logo_url=p_logo, color_principal=p_color, nombre_visible=p_nombre, texto_pie=p_texto
            where id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Entidad no encontrada'; end if;
end $$;

create or replace function plone27_bk_branding_comercio_set(p_client uuid,p_bank uuid,p_logo text,p_color text,p_nombre text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_api_clients set logo_url=p_logo, color_principal=p_color, nombre_comercial=p_nombre
            where id=p_client and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Cliente no encontrado'; end if;
end $$;

-- ---------- Webhooks gestionados por el banco ----------
create or replace function plone27_bk_webhook_crear(p_bank uuid,p_url text,p_eventos text[],p_secret text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare wid uuid; begin
  if p_eventos is null or array_length(p_eventos,1) is null or not(p_eventos <@ array['*','checkout.confirmacion_requerida','checkout.pagado','checkout.rechazado','checkout.cancelado','gasto.propuesto','gasto.aprobado','gasto.rechazado','gasto.pagado','tarea.registrada','tarea.validada','tarea.rechazada','tarea.pagada','nomina.pagada','transaction.posted']::text[]) then
    raise exception 'Eventos no válidos';
  end if;
  insert into plone27_webhooks(bank_id,url,secret,events,active) values(p_bank,p_url,p_secret,p_eventos,true)
    returning plone27_webhooks.id into wid;
  return wid; end $$;

create or replace function plone27_bk_webhook_rotar(p_bank uuid,p_id uuid,p_secret text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_webhooks set secret=p_secret where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Webhook no encontrado'; end if;
end $$;

create or replace function plone27_bk_webhook_baja(p_bank uuid,p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(delete from plone27_webhooks where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Webhook no encontrado'; end if;
end $$;

-- ---------- Cuentas de la entidad con saldo disponible ----------
create or replace function plone27_bk_cuentas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.iban),'[]'::jsonb) from (
    select a.iban, a.name as nombre, a.kind as tipo, a.status as estado, plone27_available(a.id) as disponible
    from plone27_accounts a where a.bank_id=p_bank) x $$;

-- ---------- Pagos de un cliente de API ----------
create or replace function plone27_bk_checkouts_lista(p_client uuid,p_estado text,p_limite int) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select c.id, c.client_ref, c.estado, c.importe, c.concepto, c.comision, c.creada, c.resuelta as resuelto, c.expira_at as expira
    from plone27_checkouts c
    where c.client_id=p_client and (p_estado is null or c.estado=p_estado)
    order by c.creada desc limit least(greatest(coalesce(p_limite,50),1),200)) x $$;

-- ---------- Creación de pagos: comprueba el producto, sus parámetros y las restricciones ----------
drop function if exists plone27_checkout_create(uuid,uuid,text,text,text,text,text,text,numeric,text,text,text,integer);
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_tarjeta_ref text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo_pago text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pc plone27_pasarela_config; pid uuid; pagador uuid; tarj plone27_cards; medio text:='cuenta'; destino uuid; dbank uuid; dkind text; bpag uuid; inter boolean:=false;
  com numeric:=0; pagad text:='cliente'; benef text:='propietario'; cid uuid; caduca timestamptz; mins int;
  nombre_comercio text; motivo text; begin
  select * into pc from plone27_pasarela_config where bank_id=p_bank;
  if pc.bank_id is null or not pc.activa then raise exception 'La pasarela no está activa para tu entidad'; end if;
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>pc.importe_maximo then raise exception 'Importe entre 0,01 y % Pz', pc.importe_maximo; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  mins:=coalesce(p_minutos,pc.minutos_defecto);
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if length(replace(coalesce(p_codigo_pago,''),'-',''))<>16 then raise exception 'Código de pago no válido'; end if;
  if (coalesce(p_iban_pagador,'')='') = (coalesce(p_tarjeta_ref,'')='') then raise exception 'Indica una cuenta o una tarjeta, no las dos ni ninguna'; end if;
  pid:=plone27_persona(p_dip);
  if coalesce(p_tarjeta_ref,'')<>'' then
    select cd.* into tarj from plone27_cards cd where cd.card_ref=p_tarjeta_ref;
    if tarj.id is null or tarj.status<>'active' then raise exception 'Tarjeta no válida o no activa'; end if;
    select a.bank_id into bpag from plone27_accounts a where a.id=tarj.account_id;
    if not plone27_user_can(pid,tarj.account_id,true,bpag) then raise exception 'La tarjeta no es accesible para esta persona'; end if;
    pagador:=tarj.account_id; medio:='tarjeta';
  else
    select a.id, a.bank_id into pagador, bpag from plone27_accounts a where a.iban=p_iban_pagador and a.status='active';
    if pagador is null or not plone27_user_can(pid,pagador,true,bpag) then raise exception 'Cuenta del pagador no accesible'; end if;
  end if;
  select a.id, a.kind, a.bank_id into destino, dkind, dbank from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  if not(dkind = any(pc.destinos)) then raise exception 'La pasarela de tu entidad solo cobra a cuentas de tipo: %', array_to_string(pc.destinos,', '); end if;
  inter:=dbank<>bpag;
  motivo:=plone27_checkout_bloqueado(bpag,medio,case when medio='tarjeta' then tarj.kind else null end,inter);
  if motivo is not null then raise exception '%', motivo; end if;
  if inter then
    com:=plone27_comision_calc(bpag,p_importe);
    select coalesce((select pc2.pagador from plone27_politica_comision pc2 where pc2.bank_id=bpag and pc2.producto=medio),'cliente') into pagad;
    select coalesce((select cb.beneficiario from plone27_comisiones_banco cb where cb.bank_id=bpag),'propietario') into benef;
  end if;
  select cl.name into nombre_comercio from plone27_api_clients cl where cl.id=p_client;
  caduca:=now()+make_interval(mins=>mins);
  insert into plone27_checkouts(token_hash,bank_id,banco_pagador,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
      importe,concepto,codigo_hash,codigo_expira,expira_at,medio,tarjeta,interbancaria,comision,comision_pagador,comision_beneficiario)
    values(plone27_sha(p_token),p_bank,bpag,p_client,lower(p_origen),p_client_ref,pid,pagador,destino,p_importe,p_concepto,
      plone27_sha(upper(replace(p_codigo_pago,'-',''))),caduca,caduca,medio,case when medio='tarjeta' then tarj.id else null end,inter,com,pagad,benef)
    returning plone27_checkouts.id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.confirmacion_requerida',array[bpag],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'comercio',nombre_comercio,'importe',p_importe,'concepto',p_concepto,
      'comision',com,'medio',medio,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca,'comision',com,
    'total',case when pagad='cliente' then p_importe+com else p_importe end,
    'aviso',case when com>0 then plone27_aviso_comisiones() else null end);
end $$;

-- ---------- Estado público: branding del banco pagador y del comercio ----------
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'origen',c.origen_banco,
    'banco',jsonb_build_object('nombre',coalesce(b.nombre_visible,b.name),'logo',b.logo_url,'color',b.color_principal,'texto_pie',b.texto_pie),
    'comercio',coalesce(cl.nombre_comercial,cl.name),'comercio_logo',cl.logo_url,'comercio_color',cl.color_principal,
    'medio',c.medio,'comision',c.comision,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end,
    'aviso',case when c.comision>0 then plone27_aviso_comisiones() else null end)
  from plone27_checkouts c join plone27_banks b on b.id=c.banco_pagador join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

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


do $$ begin raise notice 'Actualización 0034 aplicada correctamente.'; end $$;

commit;
