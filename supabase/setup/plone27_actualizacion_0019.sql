-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0019 · Banca online completa (segunda fase)
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0018.
-- AÑADE: beneficiarios, tarjetas del usuario, notificaciones, extracto, apertura de cuentas,
--        solicitudes y gestión de sesiones.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0019 · Banca online completa (segunda fase): beneficiarios, tarjetas del usuario,
-- notificaciones, extracto, apertura de cuentas, solicitudes y gestión de sesiones.
-- Requiere 0018. Idempotente. Todo comprueba pertenencia de la cuenta y entidad de la sesión.

-- ========== TABLAS ==========
create table if not exists plone27_beneficiarios(
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references plone27_personas,
  bank_id uuid not null references plone27_banks,
  alias text not null check(length(alias) between 1 and 60),
  iban text not null,
  created_at timestamptz not null default now(),
  unique(persona,bank_id,iban));

create table if not exists plone27_notificaciones(
  id bigint generated always as identity primary key,
  persona uuid not null references plone27_personas,
  bank_id uuid not null references plone27_banks,
  tipo text not null,
  texto text not null,
  creada timestamptz not null default now(),
  leida timestamptz);
create index if not exists plone27_notif_persona_idx on plone27_notificaciones(persona,bank_id,id);

create table if not exists plone27_solicitudes(
  id uuid primary key default gen_random_uuid(),
  persona uuid not null references plone27_personas,
  bank_id uuid not null references plone27_banks,
  tipo text not null check(tipo in('prestamo','cuenta')),
  importe numeric(18,2) not null default 0 check(importe>=0),
  cuotas int,
  motivo text,
  estado text not null default 'pendiente' check(estado in('pendiente','aprobada','rechazada')),
  clave_idem text unique,
  creada timestamptz not null default now(),
  resuelta timestamptz,
  resuelta_por uuid);

-- ========== NOTIFICACIONES AUTOMÁTICAS: cada movimiento de una cuenta avisa a sus titulares ==========
create or replace function plone27_notify_ledger() returns trigger language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare bk uuid; ib text; begin
  select a.bank_id,a.iban into bk,ib from plone27_accounts a where a.id=new.account_id;
  if bk is null then return null; end if;
  insert into plone27_notificaciones(persona,bank_id,tipo,texto)
    select m.user_id,bk,
      case when new.direction='credit' then 'ingreso' else 'cargo' end,
      case when new.direction='credit' then 'Has recibido '||new.amount::text||' Pz en '||ib
           else 'Se han cargado '||new.amount::text||' Pz en '||ib end
    from plone27_account_members m join plone27_personas p on p.id=m.user_id
    where m.account_id=new.account_id and m.role in('holder','coholder');   -- solo personas: un usuario del personal nunca bloquea un apunte
  return null; end $$;
drop trigger if exists t_notify_ledger on plone27_ledger_entries;
drop trigger if exists t_notify_ledger on plone27_ledger_entries;
create trigger t_notify_ledger after insert on plone27_ledger_entries for each row execute function plone27_notify_ledger();

-- ========== BENEFICIARIOS ==========
create or replace function plone27_user_beneficiary_add(p_user uuid,p_bank uuid,p_alias text,p_iban text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare bid uuid; begin
  if coalesce(length(p_alias),0) not between 1 and 60 then raise exception 'Alias entre 1 y 60 caracteres'; end if;
  if not exists(select 1 from plone27_accounts where iban=p_iban and status='active') then raise exception 'IBAN no válido'; end if;
  insert into plone27_beneficiarios(persona,bank_id,alias,iban) values(p_user,p_bank,p_alias,p_iban)
    on conflict(persona,bank_id,iban) do update set alias=excluded.alias
    returning plone27_beneficiarios.id into bid;
  return bid; end $$;

create or replace function plone27_user_beneficiaries(p_user uuid,p_bank uuid)
returns table(id uuid,alias text,iban text,creado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select b.id,b.alias,b.iban,b.created_at from plone27_beneficiarios b
    where b.persona=p_user and b.bank_id=p_bank order by b.alias;
end $$;

create or replace function plone27_user_beneficiary_delete(p_user uuid,p_bank uuid,p_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(delete from plone27_beneficiarios where id=p_id and persona=p_user and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Beneficiario no encontrado'; end if;
  return true; end $$;

-- ========== TARJETAS DEL USUARIO (consulta y suspensión temporal) ==========
create or replace function plone27_user_cards(p_user uuid,p_bank uuid,p_iban text)
returns table(ref text,tipo text,ultimos4 text,caduca date,estado text,limite numeric)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; begin
  select a.id into acc from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if acc is null or not plone27_user_can(p_user,acc,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select c.card_ref,c.kind,c.last4,c.expires,c.status,c.credit_limit from plone27_cards c where c.account_id=acc;
end $$;

-- El usuario solo puede suspender ('suspended') o reactivar ('active') sus tarjetas. Bloqueo y cierre los hace el banco.
create or replace function plone27_user_card_state(p_user uuid,p_bank uuid,p_ref text,p_estado text) returns text
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cid uuid; acc uuid; st text; begin
  if p_estado not in('active','suspended') then raise exception 'Estado no permitido: solo activar o suspender'; end if;
  select c.id,c.account_id,c.status into cid,acc,st from plone27_cards c where c.card_ref=p_ref for update;
  if cid is null or not plone27_user_can(p_user,acc,true,p_bank) then raise exception 'Tarjeta no encontrada'; end if;
  if st not in('active','suspended') then raise exception 'La tarjeta no se puede cambiar en su estado actual'; end if;
  update plone27_cards set status=p_estado where id=cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'card_state','card',cid::text,jsonb_build_object('persona',p_user,'estado',p_estado));
  return p_estado; end $$;

-- ========== NOTIFICACIONES DEL USUARIO ==========
create or replace function plone27_user_notifications(p_user uuid,p_bank uuid,p_solo_nuevas boolean,p_limite int)
returns table(id bigint,tipo text,texto text,creada timestamptz,leida boolean)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select n.id,n.tipo,n.texto,n.creada,(n.leida is not null)
    from plone27_notificaciones n
    where n.persona=p_user and n.bank_id=p_bank and (not coalesce(p_solo_nuevas,false) or n.leida is null)
    order by n.id desc limit least(greatest(coalesce(p_limite,50),1),200);
end $$;

create or replace function plone27_user_notifications_read(p_user uuid,p_bank uuid,p_ids bigint[]) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_notificaciones set leida=now()
            where persona=p_user and bank_id=p_bank and leida is null and (p_ids is null or id=any(p_ids)) returning 1)
  select count(*) into n from x;
  return n; end $$;

-- ========== EXTRACTO: saldo inicial, movimientos del periodo y saldo final ==========
create or replace function plone27_user_statement(p_user uuid,p_bank uuid,p_account uuid,p_desde date,p_hasta date) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare ap numeric; mov jsonb; efecto_periodo numeric; begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  if p_hasta<p_desde or (p_hasta-p_desde)>366 then raise exception 'Periodo no válido (máximo 366 días)'; end if;
  select coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) into ap
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and t.created_at<p_desde::timestamptz;
  select coalesce(sum(case when e.direction='credit' then e.amount else -e.amount end),0) into efecto_periodo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and t.created_at>=p_desde::timestamptz and t.created_at<(p_hasta+1)::timestamptz;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.fecha,x.id),'[]'::jsonb) into mov from (
    select e.id,t.created_at fecha,e.direction sentido,e.amount importe,t.kind tipo,t.memo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and t.created_at>=p_desde::timestamptz and t.created_at<(p_hasta+1)::timestamptz) x;
  return jsonb_build_object('desde',p_desde,'hasta',p_hasta,'saldo_inicial',ap,'movimientos',mov,
    'saldo_final',ap+efecto_periodo);
end $$;

-- ========== APERTURA DE CUENTA PERSONAL POR EL USUARIO (máximo 3 por entidad) ==========
create or replace function plone27_user_open_account(p_user uuid,p_bank uuid,p_nombre text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; r jsonb; aid uuid; begin
  if coalesce(length(p_nombre),0) not between 3 and 60 then raise exception 'Nombre de la cuenta: entre 3 y 60 caracteres'; end if;
  select count(*) into n from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.user_id=p_user and a.bank_id=p_bank and a.kind='personal' and a.status='active' and m.role='holder';
  if n>=3 then raise exception 'Ya tiene el máximo de cuentas personales en esta entidad'; end if;
  r:=plone27_open_account(p_bank,'personal',p_nombre,p_user,null);
  aid:=(r->>'id')::uuid;
  insert into plone27_account_members(account_id,user_id,role) values(aid,p_user,'holder') on conflict(account_id,user_id) do nothing;
  return aid; end $$;

-- ========== SOLICITUDES (préstamo o cuenta): quedan pendientes hasta que el personal las resuelva ==========
create or replace function plone27_user_request_create(p_user uuid,p_bank uuid,p_tipo text,p_importe numeric,p_cuotas int,p_motivo text,p_clave text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare sid uuid; begin
  if p_tipo not in('prestamo','cuenta') then raise exception 'Tipo de solicitud no válido'; end if;
  if p_tipo='prestamo' and (p_importe is null or p_importe<=0 or p_importe>50000) then raise exception 'Importe de préstamo entre 0 y 50.000 Pz'; end if;
  if p_tipo='prestamo' and (p_cuotas is null or p_cuotas<1 or p_cuotas>120) then raise exception 'Cuotas entre 1 y 120'; end if;
  if coalesce(length(p_motivo),0)>500 then raise exception 'Motivo demasiado largo (máximo 500)'; end if;
  insert into plone27_solicitudes(persona,bank_id,tipo,importe,cuotas,motivo,clave_idem)
    values(p_user,p_bank,p_tipo,coalesce(p_importe,0),p_cuotas,p_motivo,p_clave)
    on conflict(clave_idem) do update set clave_idem=excluded.clave_idem
    returning plone27_solicitudes.id into sid;
  return sid; end $$;

create or replace function plone27_user_requests(p_user uuid,p_bank uuid)
returns table(id uuid,tipo text,importe numeric,cuotas int,estado text,creada timestamptz,resuelta timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.id,s.tipo,s.importe,s.cuotas,s.estado,s.creada,s.resuelta
    from plone27_solicitudes s where s.persona=p_user and s.bank_id=p_bank order by s.creada desc limit 100;
end $$;

-- ========== SESIONES DEL USUARIO ==========
create or replace function plone27_user_sessions_list(p_user uuid)
returns table(id uuid,cliente text,creada timestamptz,expira timestamptz,revocada boolean,permisos text[])
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.id,c.name,s.created_at,s.expires_at,(s.revoked_at is not null),s.scopes
    from plone27_user_sessions s join plone27_api_clients c on c.id=s.client_id
    where s.platform_user_id=p_user order by s.created_at desc limit 50;
end $$;

-- Cierra todas las sesiones del usuario excepto la actual (la que hace la petición)
create or replace function plone27_user_sessions_revoke_others(p_user uuid,p_hash_actual text) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_user_sessions set revoked_at=now()
            where platform_user_id=p_user and revoked_at is null and expires_at>now() and token_hash<>p_hash_actual returning 1)
  select count(*) into n from x;
  return n; end $$;

-- Seguridad (mismo patrón; no legibles desde el panel)
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


do $$ begin raise notice 'Actualización 0019 aplicada correctamente.'; end $$;

commit;
