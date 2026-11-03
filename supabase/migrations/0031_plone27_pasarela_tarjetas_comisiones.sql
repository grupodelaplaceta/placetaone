-- Placeta One · 0031 · Pasarela con tarjeta y comisiones interbancarias.
-- Tarifa fijada por el propietario por banco; el banco del pagador decide, para cuenta y para tarjeta,
-- si la comisión la paga el cliente o la absorbe. Quién la cobra (propietario o banco del pagador) lo decide el propietario.
-- Requiere 0030. Idempotente.

-- ---------- Datos de los pagos ----------
alter table plone27_checkouts add column if not exists medio text not null default 'cuenta' check(medio in('cuenta','tarjeta'));
alter table plone27_checkouts add column if not exists tarjeta uuid references plone27_cards(id);
alter table plone27_checkouts add column if not exists interbancaria boolean not null default false;
alter table plone27_checkouts add column if not exists comision numeric(18,2) not null default 0 check(comision>=0);
alter table plone27_checkouts add column if not exists comision_pagador text not null default 'cliente' check(comision_pagador in('cliente','banco'));
alter table plone27_checkouts add column if not exists comision_beneficiario text not null default 'propietario' check(comision_beneficiario in('propietario','banco_pagador'));

-- ---------- Tarifa por banco (la fija el propietario de la pasarela) ----------
create table if not exists plone27_comisiones_banco(
  bank_id uuid primary key references plone27_banks,
  beneficiario text not null default 'propietario' check(beneficiario in('propietario','banco_pagador')),
  tipo text not null default 'fijo' check(tipo in('fijo','porcentaje')),
  valor numeric(18,4) not null default 0 check(valor>=0),
  actualizado timestamptz not null default now());

-- ---------- Política del banco: quién paga la comisión, para cuenta y para tarjeta ----------
create table if not exists plone27_politica_comision(
  bank_id uuid not null references plone27_banks,
  producto text not null check(producto in('cuenta','tarjeta')),
  pagador text not null default 'cliente' check(pagador in('cliente','banco')),
  primary key(bank_id,producto));

create or replace function plone27_comision_calc(p_bank uuid,p_importe numeric) returns numeric
language sql stable security definer set search_path=public as $$
  select coalesce((select case when c.tipo='fijo' then round(c.valor,2) else round(p_importe*c.valor/100,2) end
    from plone27_comisiones_banco c where c.bank_id=p_bank),0) $$;

-- Cuenta de comisiones del banco (se abre la primera vez)
create or replace function plone27_comision_cuenta(p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; begin
  select a.id into cid from plone27_accounts a
    where a.bank_id=p_bank and a.kind='system' and a.name='Comisiones interbancarias' limit 1;
  if cid is null then
    cid:=(plone27_open_account(p_bank,'system','Comisiones interbancarias',null,null)->>'id')::uuid;
  end if;
  return cid; end $$;

-- Política del banco (lo llama la API del banco)
create or replace function plone27_bk_politica_set(p_bank uuid,p_producto text,p_pagador text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  insert into plone27_politica_comision(bank_id,producto,pagador) values(p_bank,p_producto,p_pagador)
    on conflict(bank_id,producto) do update set pagador=excluded.pagador;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'comision_politica','bank',p_bank::text,jsonb_build_object('producto',p_producto,'pagador',p_pagador));
end $$;

-- Tarifa del banco (lo fija el propietario desde el panel)
create or replace function plone27_admin_comision_set(p_bank uuid,p_beneficiario text,p_tipo text,p_valor numeric) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  insert into plone27_comisiones_banco(bank_id,beneficiario,tipo,valor) values(p_bank,p_beneficiario,p_tipo,p_valor)
    on conflict(bank_id) do update set beneficiario=excluded.beneficiario, tipo=excluded.tipo, valor=excluded.valor, actualizado=now();
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'comision_tarifa','bank',p_bank::text,jsonb_build_object('beneficiario',p_beneficiario,'tipo',p_tipo,'valor',p_valor));
end $$;

-- ---------- Crear un pago: cuenta o tarjeta, con la comisión calculada si es interbancario ----------
drop function if exists plone27_checkout_create(uuid,uuid,text,text,text,text,text,numeric,text,text,text,integer);
create or replace function plone27_checkout_create(p_client uuid,p_bank uuid,p_origen text,p_client_ref text,p_dip text,
    p_iban_pagador text,p_tarjeta_ref text,p_iban_destino text,p_importe numeric,p_concepto text,p_token text,p_codigo text,p_minutos int)
returns jsonb language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; pagador uuid; tarj plone27_cards; medio text:='cuenta'; destino uuid; dbank uuid; inter boolean:=false;
  com numeric:=0; pagad text:='cliente'; benef text:='propietario'; cid uuid; caduca timestamptz; mins int:=coalesce(p_minutos,15); begin
  if not plone27_origen_permitido(lower(p_origen),p_client) then raise exception 'Origen no autorizado para tu cliente'; end if;
  if p_importe is null or p_importe<=0 or p_importe>50000 then raise exception 'Importe entre 0,01 y 50.000 Pz'; end if;
  if coalesce(length(p_concepto),0) not between 1 and 120 then raise exception 'Concepto entre 1 y 120 caracteres'; end if;
  if coalesce(length(p_client_ref),0) not between 1 and 80 then raise exception 'Referencia entre 1 y 80 caracteres'; end if;
  if mins not between 3 and 30 then raise exception 'Validez entre 3 y 30 minutos'; end if;
  if coalesce(length(p_codigo),0)<>6 then raise exception 'Código de verificación no válido'; end if;
  if (coalesce(p_iban_pagador,'')='') = (coalesce(p_tarjeta_ref,'')='') then raise exception 'Indica una cuenta o una tarjeta, no las dos ni ninguna'; end if;
  pid:=plone27_persona(p_dip);
  if coalesce(p_tarjeta_ref,'')<>'' then
    select cd.* into tarj from plone27_cards cd join plone27_accounts a on a.id=cd.account_id
      where cd.card_ref=p_tarjeta_ref and a.bank_id=p_bank;
    if tarj.id is null or tarj.status<>'active' then raise exception 'Tarjeta no válida o no activa'; end if;
    if not plone27_user_can(pid,tarj.account_id,true,p_bank) then raise exception 'La tarjeta no es accesible para esta persona'; end if;
    pagador:=tarj.account_id; medio:='tarjeta';
  else
    select a.id into pagador from plone27_accounts a where a.iban=p_iban_pagador and a.bank_id=p_bank;
    if pagador is null or not plone27_user_can(pid,pagador,true,p_bank) then raise exception 'Cuenta del pagador no accesible'; end if;
  end if;
  select a.id into destino from plone27_accounts a where a.iban=p_iban_destino and a.status='active';
  if destino is null then raise exception 'Cuenta destino no válida'; end if;
  select a.bank_id into dbank from plone27_accounts a where a.id=destino;
  inter:=dbank<>p_bank;
  if inter then
    com:=plone27_comision_calc(p_bank,p_importe);
    select coalesce((select pc.pagador from plone27_politica_comision pc where pc.bank_id=p_bank and pc.producto=medio),'cliente') into pagad;
    select coalesce((select cb.beneficiario from plone27_comisiones_banco cb where cb.bank_id=p_bank),'propietario') into benef;
  end if;
  caduca:=now()+make_interval(mins=>mins);
  insert into plone27_checkouts(token_hash,bank_id,client_id,origen_banco,client_ref,pagador_persona,pagador_cuenta,cuenta_destino,
      importe,concepto,codigo_hash,codigo_expira,expira_at,medio,tarjeta,interbancaria,comision,comision_pagador,comision_beneficiario)
    values(plone27_sha(p_token),p_bank,p_client,lower(p_origen),p_client_ref,pid,pagador,destino,p_importe,p_concepto,
      plone27_sha(p_codigo),caduca,caduca,medio,case when medio='tarjeta' then tarj.id else null end,inter,com,pagad,benef)
    returning plone27_checkouts.id into cid;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.codigo',array[p_bank],
    jsonb_build_object('checkout_id',cid,'client_ref',p_client_ref,'codigo',p_codigo,'importe',p_importe,'concepto',p_concepto,
      'comision',com,'expira',caduca));
  return jsonb_build_object('id',cid,'expira',caduca,'comision',com,
    'total',case when pagad='cliente' then p_importe+com else p_importe end);
end $$;

-- ---------- Estado público: añade medio, comisión y total ----------
create or replace function plone27_checkout_status(p_token text) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object('estado',case when c.estado='pendiente' and c.expira_at<now() then 'caducado' else c.estado end,
    'importe',c.importe,'concepto',c.concepto,'expira',c.expira_at,'intentos_restantes',greatest(0,3-c.intentos),
    'origen',c.origen_banco,'banco',jsonb_build_object('nombre',b.name,'logo',b.logo_url,'color',b.color_principal),
    'comercio',cl.name,'medio',c.medio,'comision',c.comision,
    'total',case when c.comision_pagador='cliente' then c.importe+c.comision else c.importe end)
  from plone27_checkouts c join plone27_banks b on b.id=c.bank_id join plone27_api_clients cl on cl.id=c.client_id
  where c.token_hash=plone27_sha(p_token) $$;

-- ---------- Confirmar: cobra con cuenta o con tarjeta, y reparte la comisión ----------
create or replace function plone27_checkout_confirm(p_token text,p_codigo text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_checkouts; tx uuid; ch uuid; ch2 uuid; tarj plone27_cards; ben_acc uuid; orig_acc uuid; begin
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
    ben_acc:=case when c.comision_beneficiario='propietario' then plone27_reserve_account() else plone27_comision_cuenta(c.bank_id) end;
    orig_acc:=case when c.comision_pagador='cliente' then c.pagador_cuenta else plone27_comision_cuenta(c.bank_id) end;
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
    return jsonb_build_object('ok',false,'error',sqlerrm,'estado','pendiente');
  end;
  update plone27_checkouts set estado='pagado',tx=tx,resuelta=now() where id=c.id;
  insert into plone27_outbox(event,bank_ids,payload) values('checkout.pagado',array[c.bank_id],
    jsonb_build_object('checkout_id',c.id,'client_ref',c.client_ref,'importe',c.importe,'comision',c.comision,'transaccion',tx));
  return jsonb_build_object('ok',true,'transaccion',tx,'estado','pagado');
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
