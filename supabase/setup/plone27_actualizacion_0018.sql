-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0018 · API completa de banca online
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0017.
-- AÑADE: ficha de cuenta, transferencias programadas, certificado de recibo, RBU, previsión personal,
--        planes, búsqueda de destinatario por IBAN y búsqueda por DIP para el banco.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0018 · API completa de banca online (ficha de cuenta, programadas, certificados, RBU,
-- previsión personal, planes, búsqueda de destinatarios y búsqueda por DIP para el banco).
-- Requiere 0017. Idempotente. Todas las funciones de usuario comprueban pertenencia y entidad.

-- Idempotencia para las transferencias programadas (un reintento no crea otra programación)
alter table plone27_scheduled add column if not exists clave_idem text unique;

-- Ficha de una cuenta del usuario
create or replace function plone27_user_account_detail(p_user uuid,p_account uuid,p_bank uuid)
returns table(iban text,nombre text,tipo text,estado text,rol text,saldo numeric,reservado numeric,disponible numeric,limite_diario numeric,descubierto boolean)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select a.iban,a.name,a.kind,a.status,
      (select m.role from plone27_account_members m where m.account_id=a.id and m.user_id=p_user limit 1),
      b.booked,b.reserved,b.booked-b.reserved,a.daily_limit,a.allow_negative
    from plone27_accounts a join plone27_account_balances b on b.account_id=a.id where a.id=p_account;
end $$;

-- Transferencia programada (única o periódica). Solo desde cuentas del usuario con permiso de escritura.
create or replace function plone27_user_scheduled_create(p_user uuid,p_bank uuid,p_from_iban text,p_to_iban text,p_amount numeric,
  p_run_at timestamptz,p_recurrence interval,p_memo text,p_clave text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; t uuid; sid uuid; begin
  select a.id into f from plone27_accounts a where a.iban=p_from_iban;
  if f is null or not plone27_user_can(p_user,f,true,p_bank) then raise exception 'Cuenta de origen no accesible'; end if;
  select a.id into t from plone27_accounts a where a.iban=p_to_iban and a.status='active';
  if t is null then raise exception 'Cuenta destino no válida'; end if;
  if t=f then raise exception 'Origen y destino no pueden coincidir'; end if;
  if p_run_at < now() - interval '1 minute' then raise exception 'La fecha debe ser futura'; end if;
  if p_recurrence is not null and p_recurrence < interval '1 day' then raise exception 'La periodicidad mínima es de un día'; end if;
  insert into plone27_scheduled(from_account,to_account,amount,run_at,recurrence,memo,clave_idem)
    values(f,t,p_amount,p_run_at,p_recurrence,coalesce(p_memo,'Transferencia programada'),p_clave)
    on conflict(clave_idem) do update set clave_idem=excluded.clave_idem
    returning plone27_scheduled.id into sid;
  return sid; end $$;

create or replace function plone27_user_scheduled_list(p_user uuid,p_bank uuid)
returns table(id uuid,origen text,destino text,importe numeric,proxima timestamptz,periodicidad interval,estado text,concepto text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.id,fa.iban,ta.iban,s.amount,s.run_at,s.recurrence,s.status,s.memo
    from plone27_scheduled s join plone27_accounts fa on fa.id=s.from_account join plone27_accounts ta on ta.id=s.to_account
    where s.status='active' and plone27_user_can(p_user,s.from_account,false,p_bank)
    order by s.run_at;
end $$;

create or replace function plone27_user_scheduled_cancel(p_user uuid,p_bank uuid,p_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; begin
  select s.from_account into f from plone27_scheduled s where s.id=p_id and s.status='active';
  if f is null or not plone27_user_can(p_user,f,true,p_bank) then raise exception 'Programación no encontrada'; end if;
  update plone27_scheduled set status='cancelled' where id=p_id;
  return true; end $$;

-- Certificado de un recibo propio (el recibo debe ser de una cuenta del usuario en su entidad)
create or replace function plone27_user_receipt_certificate(p_user uuid,p_bank uuid,p_ref text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare rid uuid; acc uuid; begin
  select r.id,r.account_id into rid,acc from plone27_tax_receipts r where r.ref=p_ref;
  if rid is null or not plone27_user_can(p_user,acc,false,p_bank) then raise exception 'Recibo no encontrado'; end if;
  return plone27_receipt_certificate(rid); end $$;

-- RBU del usuario en su entidad
create or replace function plone27_user_rbu_list(p_user uuid,p_bank uuid)
returns table(id uuid,semana date,importe numeric,estado text,caduca date,cartera text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select b.id,b.week_start,b.amount,b.status,b.expires_on,wa.iban
    from plone27_rbu_bonuses b join plone27_accounts wa on wa.id=b.wallet_account
    where b.owner_user=p_user and wa.bank_id=p_bank order by b.week_start desc limit 52;
end $$;

create or replace function plone27_user_rbu_claim(p_user uuid,p_bank uuid,p_bonus uuid,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare w uuid; begin
  select b.wallet_account into w from plone27_rbu_bonuses b join plone27_accounts a on a.id=b.wallet_account
    where b.id=p_bonus and a.bank_id=p_bank and b.owner_user=p_user;
  if w is null then raise exception 'Bono no encontrado'; end if;
  return plone27_rbu_claim(p_bonus,p_user,p_key); end $$;

-- Previsión de los movimientos del usuario (solo de sus cuentas)
create or replace function plone27_user_previsiones(p_user uuid,p_bank uuid,p_desde date,p_hasta date)
returns table(fecha date,tipo text,referencia text,iban text,importe numeric,estado text,detalle text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select p.fecha,p.tipo,p.referencia,p.iban,p.importe,p.estado,p.detalle
    from plone27_previsiones(p_desde,p_hasta) p
    where p.cuenta in (select ua.id from plone27_user_accounts(p_user,p_bank) ua)
    order by p.fecha,p.tipo;
end $$;

-- Planes a plazos y suscripciones en los que el usuario es deudor (en su entidad)
create or replace function plone27_user_plans(p_user uuid,p_bank uuid)
returns table(id uuid,tipo text,cuenta text,capital numeric,tasa_anual numeric,cuotas int,estado text,proxima date)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select p.id,p.kind,a.iban,p.principal,p.annual_rate_pct,p.installments,p.status,p.next_due
    from plone27_plans p join plone27_accounts a on a.id=p.debtor_account
    where a.bank_id=p_bank and plone27_user_can(p_user,p.debtor_account,false,p_bank)
    order by p.created_at desc;
end $$;

-- Búsqueda de destinatario por IBAN: no revela el tipo de cuenta ni más datos que el titular abreviado
create or replace function plone27_lookup_iban(p_iban text) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare r record; begin
  select a.name,b.code into r from plone27_accounts a left join plone27_banks b on b.id=a.bank_id
    where a.iban=p_iban and a.status='active';
  if r is null then return jsonb_build_object('existe',false); end if;
  return jsonb_build_object('existe',true,'entidad',r.code,'titular',left(coalesce(r.name,''),2)||'***'); end $$;

-- Búsqueda por DIP para el banco (servidor). Solo devuelve cuentas de SU entidad.
-- La respuesta es igual tanto si el DIP no existe como si no tiene cuentas en ese banco.
create or replace function plone27_bk_buscar_dip(p_client uuid,p_dip text)
returns table(iban text,nombre text,tipo text,rol text,estado text)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d text:=plone27_normalizar_dip(p_dip); bk uuid; pid uuid; begin
  select c.bank_id into bk from plone27_api_clients c where c.id=p_client;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'bk_buscar_dip','client',p_client::text,jsonb_build_object('dip_hash',plone27_dip_hash(d)));
  if d !~ '^[A-Z0-9]{5,20}$' then return; end if;
  select p.id into pid from plone27_personas p where p.dip=d;
  if pid is null then return; end if;
  return query select a.iban,a.name,a.kind,m.role,a.status
    from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.user_id=pid and a.bank_id=bk order by a.created_at;
end $$;

-- Seguridad (mismo patrón; el DIP y los tokens no se leen desde el panel)
do $$ declare t text; f text; v text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces','plone27_personas') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;


do $$ begin raise notice 'Actualización 0018 aplicada correctamente.'; end $$;

commit;
