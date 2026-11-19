-- Placeta One · 0033 · La pasarela es un producto por banco para cuentas de empresa e institucionales.
-- Código de pago que el banco del pagador canjea en su propia app. Restricciones por banco (medios, tipos de tarjeta,
-- modalidades y operaciones). Aviso de comisiones. Requiere 0032. Idempotente.

-- ---------- Código de pago ----------
create unique index if not exists plone27_checkouts_codigo_ux on plone27_checkouts(codigo_hash);

-- ---------- Restricciones que cada banco aplica a sus clientes ----------
create table if not exists plone27_restricciones_pago(
  bank_id uuid not null references plone27_banks,
  tipo text not null check(tipo in('medio','tarjeta','modalidad','operacion')),
  valor text not null,
  bloqueado boolean not null default true,
  actualizado timestamptz not null default now(),
  primary key(bank_id,tipo,valor));

create or replace function plone27_restriccion_activa(p_bank uuid,p_tipo text,p_valor text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_restricciones_pago r
    where r.bank_id=p_bank and r.tipo=p_tipo and r.valor=p_valor and r.bloqueado) $$;

-- Motivo por el que el banco no permite el pago, o nulo si está permitido
create or replace function plone27_checkout_bloqueado(p_bank uuid,p_medio text,p_tkind text,p_inter boolean) returns text
language plpgsql stable security definer set search_path=public as $$
begin
  if p_medio='cuenta' and plone27_restriccion_activa(p_bank,'medio','cuenta') then return 'Tu banco no permite pagos desde cuenta'; end if;
  if p_medio='tarjeta' and plone27_restriccion_activa(p_bank,'medio','tarjeta') then return 'Tu banco no permite pagos con tarjeta'; end if;
  if p_medio='tarjeta' and plone27_restriccion_activa(p_bank,'tarjeta',p_tkind) then return 'Tu banco no permite este tipo de tarjeta'; end if;
  if p_medio='tarjeta' and p_tkind='credit' and plone27_restriccion_activa(p_bank,'modalidad','diferida') then return 'Tu banco no permite pagos diferidos'; end if;
  if p_medio='tarjeta' and p_tkind<>'credit' and plone27_restriccion_activa(p_bank,'modalidad','inmediata') then return 'Tu banco no permite pagos inmediatos con tarjeta'; end if;
  if p_inter and plone27_restriccion_activa(p_bank,'operacion','interbancario') then return 'Tu banco no permite pagos interbancarios'; end if;
  return null; end $$;

-- El banco activa o desactiva una restricción (valores permitidos fijos)
create or replace function plone27_bk_restriccion_set(p_bank uuid,p_tipo text,p_valor text,p_bloqueado boolean) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not((p_tipo='medio' and p_valor in('cuenta','tarjeta'))
      or (p_tipo='tarjeta' and p_valor in('digital','physical','credit','prepago'))
      or (p_tipo='modalidad' and p_valor in('inmediata','diferida'))
      or (p_tipo='operacion' and p_valor='interbancario')) then
    raise exception 'Restricción no válida';
  end if;
  insert into plone27_restricciones_pago(bank_id,tipo,valor,bloqueado) values(p_bank,p_tipo,p_valor,p_bloqueado)
    on conflict(bank_id,tipo,valor) do update set bloqueado=excluded.bloqueado, actualizado=now();
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'restriccion_pago','bank',p_bank::text,jsonb_build_object('tipo',p_tipo,'valor',p_valor,'bloqueado',p_bloqueado));
end $$;

-- Texto de aviso: solo cuando hay comisión visible
create or replace function plone27_aviso_comisiones() returns text
language sql immutable as $$
  select 'Tu entidad de pagos del ecosistema Placeta puede aplicar otras comisiones extra a las mostradas.' $$;

-- ---------- Crear el pago con código ----------
drop function if exists plone27_checkout_create(uuid,uuid,text,text,text,text,text,text,numeric,text,text,integer);
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_tarjeta_ref text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo_pago text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; pagador uuid; tarj plone27_cards; medio text:='cuenta'; destino uuid; dbank uuid; dkind text; bpag uuid; inter boolean:=false;
  com numeric:=0; pagad text:='cliente'; benef text:='propietario'; cid uuid; caduca timestamptz; mins int:=coalesce(p_minutos,15);
  nombre_comercio text; motivo text; begin
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>50000 then raise exception 'Importe entre 0,01 y 50.000 Pz'; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
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
  if dkind not in('business','system') then raise exception 'La pasarela solo cobra a cuentas de empresa o institucionales'; end if;
  inter:=dbank<>bpag;
  motivo:=plone27_checkout_bloqueado(bpag,medio,case when medio='tarjeta' then tarj.kind else null end,inter);
  if motivo is not null then raise exception '%', motivo; end if;
  if inter then
    com:=plone27_comision_calc(bpag,p_importe);
    select coalesce((select pc.pagador from plone27_politica_comision pc where pc.bank_id=bpag and pc.producto=medio),'cliente') into pagad;
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

-- ---------- El banco canjea el código en su app: ve el pago antes de aprobarlo ----------
create or replace function plone27_checkout_por_codigo(p_bank uuid,p_codigo text,p_dip text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; pid uuid; motivo text; begin
  select * into c from plone27_checkouts where codigo_hash=plone27_sha(upper(replace(coalesce(p_codigo,''),'-','')));
  if c.id is null or c.banco_pagador<>p_bank then raise exception 'Código no válido para tu entidad'; end if;
  if c.estado<>'pendiente' or c.expira_at<now() then raise exception 'El código ya no es válido'; end if;
  pid:=plone27_persona(p_dip);
  if not plone27_user_can(pid,c.pagador_cuenta,true,p_bank) then raise exception 'La persona no puede autorizar esta cuenta'; end if;
  motivo:=plone27_checkout_bloqueado(p_bank,c.medio,case when c.medio='tarjeta' then (select cd.kind from plone27_cards cd where cd.id=c.tarjeta) else null end,c.interbancaria);
  return jsonb_build_object('checkout_id',c.id,
    'comercio',(select cl.name from plone27_api_clients cl where cl.id=c.client_id),
    'importe',c.importe,'concepto',c.concepto,'medio',c.medio,'comision',c.comision,'comision_pagador',c.comision_pagador,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end,
    'aviso',case when c.comision>0 then plone27_aviso_comisiones() else null end,
    'expira',c.expira_at,
    'origen_pago',case when c.medio='tarjeta' then jsonb_build_object('tarjeta_ultimos4',(select cd.last4 from plone27_cards cd where cd.id=c.tarjeta))
                       else jsonb_build_object('iban',(select a.iban from plone27_accounts a where a.id=c.pagador_cuenta)) end,
    'bloqueado',motivo);
end $$;

-- ---------- Estado público: añade el aviso ----------
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'origen',c.origen_banco,
    'banco',jsonb_build_object('nombre',b.name,'logo',b.logo_url,'color',b.color_principal),
    'comercio',cl.name,'medio',c.medio,'comision',c.comision,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end,
    'aviso',case when c.comision>0 then plone27_aviso_comisiones() else null end)
  from plone27_checkouts c join plone27_banks b on b.id=c.banco_pagador join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

-- ---------- Resolución: el banco aprueba; se vuelve a comprobar la restricción por si cambió ----------
create or replace function plone27_checkout_resolver(p_checkout uuid,p_bank_pagador uuid,p_dip text,p_decision text,p_motivo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; pid uuid; tx uuid; ch uuid; ch2 uuid; tarj plone27_cards; ben_acc uuid; orig_acc uuid; bloq text; begin
  select * into c from plone27_checkouts where id=p_checkout for update;
  if c.id is null or c.banco_pagador<>p_bank_pagador then raise exception 'Pago no encontrado'; end if;
  if c.estado<>'pendiente' then raise exception 'Este pago ya no está pendiente (%)', c.estado; end if;
  if c.expira_at<now() then
    update plone27_checkouts set estado='caducado', resuelta=now() where id=c.id;
    return jsonb_build_object('estado','caducado');
  end if;
  if p_decision not in('aprobado','rechazado') then raise exception 'Decisión no válida'; end if;
  pid:=plone27_persona(p_dip);
  if not plone27_user_can(pid,c.pagador_cuenta,true,c.banco_pagador) then raise exception 'La persona no puede autorizar esta cuenta'; end if;
  if p_decision='rechazado' then
    update plone27_checkouts set estado='rechazado', resuelta=now() where id=c.id;
    insert into plone27_outbox(event,bank_ids,payload) values('checkout.rechazado',array[c.bank_id],
      jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'motivo',p_motivo));
    return jsonb_build_object('estado','rechazado');
  end if;
  bloq:=plone27_checkout_bloqueado(c.banco_pagador,c.medio,case when c.medio='tarjeta' then (select cd.kind from plone27_cards cd where cd.id=c.tarjeta) else null end,c.interbancaria);
  if bloq is not null then return jsonb_build_object('estado','pendiente','error',bloq); end if;
  begin
    ben_acc:=case when c.comision_beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(c.banco_pagador) end;
    orig_acc:=case when c.comision_pagador='cliente' then c.pagador_cuenta else plone27_comision_cuenta(c.banco_pagador) end;
    if c.medio='tarjeta' then
      select * into tarj from plone27_cards where id=c.tarjeta;
      if tarj.kind='prepago' then ch:=plone27_prepago_authorize(tarj.id,c.importe,c.cuenta_destino);
      else ch:=plone27_card_authorize(tarj.id,c.importe,c.cuenta_destino,null); end if;
      tx:=plone27_card_settle('checkout:'||c.id::text,ch,null);
      if c.comision>0 then
        if c.comision_pagador='cliente' then
          if tarj.kind='prepago' then ch2:=plone27_prepago_authorize(tarj.id,c.comision,ben_acc);
          else ch2:=plone27_card_authorize(tarj.id,c.comision,ben_acc,null); end if;
          perform plone27_card_settle('checkout-com:'||c.id::text,ch2,null);
        elsif orig_acc<>ben_acc then
          perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
        end if;
      end if;
    else
      tx:=plone27_transfer('checkout:'||c.id::text,c.pagador_cuenta,c.cuenta_destino,c.importe,c.concepto,null);
      if c.comision>0 and orig_acc<>ben_acc then
        perform plone27_transfer('checkout-com:'||c.id::text,orig_acc,ben_acc,c.comision,'Comisión interbancaria',null);
      end if;
    end if;
  exception when others then
    return jsonb_build_object('estado','pendiente','error',sqlerrm);
  end;
  update plone27_checkouts set estado='pagado', tx=tx, resuelta=now() where id=c.id;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.pagado',
    case when c.bank_id=c.banco_pagador then array[c.bank_id] else array[c.bank_id,c.banco_pagador] end,
    jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'importe',c.importe,'comision',c.comision,'transaccion',tx));
  return jsonb_build_object('estado','pagado','transaccion',tx);
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
