-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN: últimos tres cambios de base de datos (0015, 0016 y 0017) en un solo archivo
--
-- REQUISITO: la base ya tiene las migraciones 0001 a 0014 aplicadas.
-- QUÉ AÑADE:
--   0015  Previsión de movimientos programados e indicadores del panel.
--   0016  API para bancos: sesiones de usuario aisladas, firma de servidor, orígenes de navegador.
--   0017  El DIP como identificador de la persona; cada entidad solo ve sus cuentas.
-- SEGURIDAD: todo va en una transacción. Si algo falla, no queda nada aplicado a medias.
-- REEJECUCIÓN: es seguro volver a ejecutarlo. Las funciones y vistas se recrean; las tablas y columnas
--   se crean solo si faltan. La clave de auditoría del DIP (dip_pepper) se genera una sola vez.
-- ATENCIÓN: la 0017 elimina la tabla plone27_client_users de la 0016 (no tiene datos en un entorno nuevo).
--   Si ya hay vinculaciones creadas con la 0016, vuelve a vincularlas con el DIP después de aplicar la 0017.
-- =====================================================================================================

begin;

-- ==================== 0015_plone27_previsiones.sql ====================
-- Placeta One · 0015 · Previsión de movimientos programados e indicadores del panel. Requiere 0014. Idempotente.

-- Previsión: todo lo que va a ocurrir en un rango de fechas, con si la cuenta puede pagarlo.
create or replace function plone27_previsiones(p_desde date,p_hasta date) returns table(
  fecha date, tipo text, referencia text, cuenta uuid, iban text, nombre text, importe numeric, estado text, detalle text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
  select u.* from (
    -- Impuestos: recibos pendientes (vencidos o con vencimiento en el rango)
    select r.due_date, 'Impuesto'::text, (ru.code||' · '||coalesce(r.ref,'sin referencia'))::text, r.account_id, a.iban, a.name,
           (r.amount-r.paid_amount)::numeric,
           (case when r.due_date<current_date then 'vencido'
                 when plone27_collectable(r.account_id,r.amount-r.paid_amount) then 'cobrable' else 'sin fondos' end)::text,
           ('Vence el '||r.due_date::text)::text
    from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
      join plone27_tax_rules ru on ru.id=v.rule_id join plone27_accounts a on a.id=r.account_id
    where r.status in('issued','partial') and r.amount-r.paid_amount>0 and r.due_date between p_desde and p_hasta
    union all
    -- Cuotas de planes a plazos
    select i.due_date, 'Cuota'::text, ('Plan '||left(p.id::text,8)||' · cuota '||i.seq)::text, p.debtor_account, a.iban, a.name,
           (i.principal_part+i.interest_part)::numeric,
           (case when i.due_date<current_date then 'vencido'
                 when plone27_collectable(p.debtor_account,i.principal_part+i.interest_part) then 'cobrable' else 'sin fondos' end)::text,
           ('Capital '||i.principal_part::text||' · interés '||i.interest_part::text)::text
    from plone27_plan_items i join plone27_plans p on p.id=i.plan_id join plone27_accounts a on a.id=p.debtor_account
    where i.status='pending' and p.status in('active','past_due') and i.due_date between p_desde and p_hasta
    union all
    -- Suscripciones: próximo cobro
    select p.next_due, 'Suscripción'::text, ('Suscripción '||left(p.id::text,8))::text, p.debtor_account, a.iban, a.name, p.principal::numeric,
           (case when plone27_collectable(p.debtor_account,p.principal) then 'cobrable' else 'sin fondos' end)::text,
           'Cobro periódico al beneficiario'::text
    from plone27_plans p join plone27_accounts a on a.id=p.debtor_account
    where p.kind='subscription' and p.status in('active','past_due') and p.next_due between p_desde and p_hasta
    union all
    -- Nóminas: bruto más cotización de empresa, desde la cuenta empleadora
    select c.next_pay, 'Nómina'::text, ('Contrato '||left(c.id::text,8))::text, c.employer_account, a.iban, a.name,
           (c.gross_monthly+coalesce(plone27_tax_calc(plone27_active_version('COT_EMP',c.next_pay),c.gross_monthly),0))::numeric,
           (case when plone27_collectable(c.employer_account,c.gross_monthly+coalesce(plone27_tax_calc(plone27_active_version('COT_EMP',c.next_pay),c.gross_monthly),0))
                 then 'cobrable' else 'sin fondos' end)::text,
           'Bruto más cotización de empresa'::text
    from plone27_contracts c join plone27_accounts a on a.id=c.employer_account
    where c.status='active' and c.next_pay between p_desde and p_hasta
    union all
    -- Transferencias programadas, con sus repeticiones dentro del rango (hasta 240)
    select (s.run_at+k.n*coalesce(s.recurrence,interval '0'))::date, 'Transferencia programada'::text, coalesce(s.memo,'Programada')::text,
           s.from_account, a.iban, a.name, s.amount::numeric,
           (case when plone27_collectable(s.from_account,s.amount) then 'cobrable' else 'sin fondos' end)::text,
           (case when s.recurrence is null then 'Única' else 'Recurrente' end)::text
    from plone27_scheduled s join plone27_accounts a on a.id=s.from_account
      cross join lateral generate_series(0, case when s.recurrence is null then 0 else 240 end) k(n)
    where s.status='active' and (s.run_at+k.n*coalesce(s.recurrence,interval '0'))::date between p_desde and p_hasta
    union all
    -- Cierres mensuales (el del mes en curso y el siguiente)
    select x.f, 'Cierre mensual'::text, ('Cierre de '||to_char(x.m-interval '1 month','YYYY-MM'))::text, null::uuid, null::text, null::text, null::numeric,
           (case when exists(select 1 from plone27_periodos pp where pp.periodo=(x.m-interval '1 month')::date and pp.estado='cerrado')
                 then 'cerrado' else 'programado' end)::text,
           'Liquida el IVA y los impuestos periódicos del mes anterior'::text
    from (select make_date(extract(year from ms.m)::int, extract(month from ms.m)::int,
                 (plone27_setting('dia_cierre')#>>'{}')::int) f, ms.m
          from (select date_trunc('month',current_date) m union all select date_trunc('month',current_date)+interval '1 month') ms) x
    where x.f between p_desde and p_hasta
    union all
    -- IAEP: cuota fija de cada actividad, emitida el día 1 de cada mes
    select (date_trunc('month',current_date)+interval '1 month')::date, 'IAEP mensual'::text,
           ('Actividades activas: '||count(*))::text, null::uuid, null::text, null::text, coalesce(sum(v.rate),0)::numeric,
           'estimado'::text, 'Cuota fija por categoría'::text
    from plone27_activities a join plone27_tax_rules ru on ru.code='IAEP'
      join plone27_tax_rule_versions v on v.rule_id=ru.id and v.scope_op=a.category and v.status='published'
    where a.status='active' and (date_trunc('month',current_date)+interval '1 month')::date between p_desde and p_hasta
    having count(*)>0
    union all
    -- Deudas reconocidas (incluidos intereses de demora y recargos)
    select d.due_date, 'Deuda'::text, coalesce(d.reason,'Deuda')::text, d.account_id, a.iban, a.name,
           (d.principal+d.authorized_charges-d.paid)::numeric,
           (case when d.due_date<current_date then 'vencido'
                 when plone27_collectable(d.account_id,d.principal+d.authorized_charges-d.paid) then 'cobrable' else 'sin fondos' end)::text,
           'Deuda reconocida'::text
    from plone27_debts d join plone27_accounts a on a.id=d.account_id
    where not d.disputed and d.paid<d.principal+d.authorized_charges and d.due_date between p_desde and p_hasta
    union all
    -- RBU sin reclamar: caduca en esa fecha
    select b.expires_on, 'RBU sin reclamar'::text, ('Bono semana '||b.week_start::text)::text, b.wallet_account, a.iban, a.name, b.amount::numeric,
           'disponible'::text, 'Si no se reclama, caduca'::text
    from plone27_rbu_bonuses b join plone27_accounts a on a.id=b.wallet_account
    where b.status='available' and b.expires_on between p_desde and p_hasta
    union all
    -- IVA estimado del mes en curso: base devengada por el tipo general (sin deducir compras)
    select (date_trunc('month',current_date)+interval '1 month -1 day')::date, 'IVA estimado'::text, 'Mes en curso'::text,
           null::uuid, null::text, null::text,
           round(coalesce((select sum(s.base) from plone27_sales s where s.created_at>=date_trunc('month',current_date)
                           and s.created_at<date_trunc('month',current_date)+interval '1 month'),0)
                 *coalesce((select v.rate from plone27_tax_rule_versions v join plone27_tax_rules ru on ru.id=v.rule_id
                            where ru.code='IVA' and v.status='published' and v.scope_op is null order by v.valid_from desc limit 1),0)/100,2)::numeric,
           'estimado'::text, 'Base devengada del mes × tipo general, sin deducir compras'::text
    where (date_trunc('month',current_date)+interval '1 month -1 day')::date between p_desde and p_hasta
  ) u order by u.fecha, u.tipo;
end $$;

-- Indicadores para el panel principal
create or replace function plone27_kpis() returns jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'recibos_pendientes',(select count(*) from plone27_tax_receipts where status in('issued','partial')),
    'recibos_pendientes_importe',(select coalesce(sum(amount-paid_amount),0) from plone27_tax_receipts where status in('issued','partial')),
    'recibos_vencidos',(select count(*) from plone27_tax_receipts where status in('issued','partial') and due_date<current_date),
    'cuentas_activas',(select count(*) from plone27_accounts where status='active'),
    'planes_activos',(select count(*) from plone27_plans where status in('active','past_due')),
    'cuotas_pendientes_importe',(select coalesce(sum(principal_part+interest_part),0) from plone27_plan_items where status='pending'),
    'contratos_activos',(select count(*) from plone27_contracts where status='active'),
    'rbu_disponible',(select coalesce(sum(amount),0) from plone27_rbu_bonuses where status='available'),
    'hallazgos_iva_abiertos',(select count(*) from plone27_iva_findings where status in('abierto','presumido')),
    'declaraciones_retenidas',(select count(*) from plone27_declaraciones where estado='retenida'),
    'incidencias_abiertas',(select count(*) from plone27_incidents where status='open'),
    'certificacion',(plone27_certification_report()->>'estado'),
    'ultimo_cierre',(select max(periodo) from plone27_periodos where estado='cerrado'))
$$;

-- ==================== 0016_plone27_api_bancos.sql ====================
-- Antes de recrear las funciones de la 0016 se eliminan sus firmas: si la base ya tiene la 0017,
-- PostgreSQL no permite renombrar parámetros con CREATE OR REPLACE (error 42P13).
drop function if exists plone27_client_user(uuid,text);
drop function if exists plone27_session_open(uuid,text,text,text[],int);
drop function if exists plone27_session_check(text);
drop function if exists plone27_user_can(uuid,uuid,boolean);
drop function if exists plone27_user_accounts(uuid);
drop function if exists plone27_user_transactions(uuid,uuid,bigint,int);
drop function if exists plone27_user_receipts(uuid,uuid);
drop function if exists plone27_user_transfer(text,uuid,text,text,numeric,text);
drop function if exists plone27_client_link_account(uuid,text,uuid,text);
-- Placeta One · 0016 · API para aplicaciones de bancos con aislamiento por usuario.
-- Niveles: servidor del banco (clave + firma HMAC) → sesión de usuario (token opaco, corta) → datos solo de sus cuentas.
-- Requiere 0015. Idempotente.

alter table plone27_api_clients add column if not exists signing_secret text;   -- secreto de firma (solo servidor; nunca se devuelve)

create table if not exists plone27_api_nonces(
  client_id uuid not null references plone27_api_clients,
  nonce text not null,
  at timestamptz not null default now(),
  primary key(client_id,nonce));

create table if not exists plone27_client_origins(
  client_id uuid not null references plone27_api_clients,
  origin text not null check(origin ~ '^https?://[^/]+$'),         -- orígenes de navegador autorizados para ese cliente
  created_at timestamptz not null default now(),
  primary key(client_id,origin));

-- Usuario del banco → usuario de la plataforma. Un mismo id externo en dos bancos son dos usuarios distintos.
create table if not exists plone27_client_users(
  client_id uuid not null references plone27_api_clients,
  external_id text not null check(length(external_id) between 1 and 128),
  platform_user_id uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now(),
  primary key(client_id,external_id));

create table if not exists plone27_user_sessions(
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references plone27_api_clients,
  platform_user_id uuid not null,
  token_hash text not null unique,                                 -- solo el hash del token
  scopes text[] not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  last_used_at timestamptz);
create index if not exists plone27_user_sessions_user_idx on plone27_user_sessions(platform_user_id);

-- Identidad de usuario para un id externo (se crea la primera vez)
create or replace function plone27_client_user(p_client uuid,p_external text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u uuid; begin
  insert into plone27_client_users(client_id,external_id) values(p_client,p_external) on conflict(client_id,external_id) do nothing;
  select platform_user_id into u from plone27_client_users where client_id=p_client and external_id=p_external;
  return u; end $$;

create or replace function plone27_session_open(p_client uuid,p_external text,p_hash text,p_scopes text[],p_ttl int) returns timestamptz
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u uuid; exp timestamptz; begin
  if p_ttl<1 or p_ttl>60 then raise exception 'TTL fuera de rango (1 a 60 minutos)'; end if;
  u:=plone27_client_user(p_client,p_external);
  exp:=now()+make_interval(mins=>p_ttl);
  insert into plone27_user_sessions(client_id,platform_user_id,token_hash,scopes,expires_at) values(p_client,u,p_hash,p_scopes,exp);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(null,'session_open','client',p_client::text,jsonb_build_object('usuario',u,'scopes',p_scopes,'minutos',p_ttl));
  return exp; end $$;

-- Valida un token: solo sesiones vigentes, no revocadas y de clientes activos
create or replace function plone27_session_check(p_hash text) returns table(client_id uuid,user_id uuid,scopes text[],rate_limit int)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.client_id,s.platform_user_id,s.scopes,c.rate_limit
    from plone27_user_sessions s join plone27_api_clients c on c.id=s.client_id
    where s.token_hash=p_hash and s.revoked_at is null and s.expires_at>now() and c.active;
end $$;

create or replace function plone27_session_revoke(p_hash text) returns boolean
language sql security definer set search_path=public as $$
  with x as (update plone27_user_sessions set revoked_at=now() where token_hash=p_hash and revoked_at is null returning 1)
  select exists(select 1 from x) $$;

-- Autorización central: el usuario pertenece a la cuenta (y puede escribir, si se pide)
create or replace function plone27_user_can(p_user uuid,p_account uuid,p_write boolean) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.account_id=p_account and m.user_id=p_user and a.status='active'
      and (not p_write or m.role in('holder','coholder'))) $$;

create or replace function plone27_user_accounts(p_user uuid) returns table(id uuid,iban text,nombre text,tipo text,rol text,saldo numeric,disponible numeric)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select a.id,a.iban,a.name,a.kind,m.role,b.booked,b.booked-b.reserved
    from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    join plone27_account_balances b on b.account_id=a.id
    where m.user_id=p_user and a.status='active' order by a.created_at;
end $$;

create or replace function plone27_user_transactions(p_user uuid,p_account uuid,p_antes bigint,p_limite int)
returns table(id bigint,fecha timestamptz,sentido text,importe numeric,tipo text,memo text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false) then raise exception 'Cuenta no accesible'; end if;
  return query select e.id,e.created_at,e.direction,e.amount,t.kind,t.memo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and (p_antes is null or e.id<p_antes)
    order by e.id desc limit least(greatest(p_limite,1),100);
end $$;

create or replace function plone27_user_receipts(p_user uuid,p_account uuid)
returns table(ref text,impuesto text,base numeric,importe numeric,pagado numeric,estado text,vence date,creado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false) then raise exception 'Cuenta no accesible'; end if;
  return query select r.ref,ru.code,r.base,r.amount,r.paid_amount,r.status,r.due_date,r.created_at
    from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
    join plone27_tax_rules ru on ru.id=v.rule_id
    where r.account_id=p_account order by r.created_at desc limit 200;
end $$;

-- Transferencia ordenada por el usuario: el origen debe ser una cuenta suya con permiso de escritura
create or replace function plone27_user_transfer(p_key text,p_user uuid,p_from_iban text,p_to_iban text,p_amount numeric,p_memo text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; t uuid; begin
  select id into f from plone27_accounts where iban=p_from_iban;
  if f is null or not plone27_user_can(p_user,f,true) then raise exception 'Cuenta de origen no accesible'; end if;
  select id into t from plone27_accounts where iban=p_to_iban and status='active';
  if t is null then raise exception 'Cuenta destino no válida'; end if;
  if t=f then raise exception 'Origen y destino no pueden coincidir'; end if;
  return plone27_transfer(p_key,f,t,p_amount,coalesce(p_memo,'Transferencia'),p_user);
end $$;

-- Alta de un usuario del banco en una de sus cuentas (lo hace el servidor del banco)
create or replace function plone27_client_link_account(p_client uuid,p_external text,p_account uuid,p_role text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u uuid; bk uuid; begin
  select bank_id into bk from plone27_api_clients where id=p_client;
  if not exists(select 1 from plone27_accounts where id=p_account and bank_id=bk) then raise exception 'La cuenta no pertenece a la entidad del cliente'; end if;
  if p_role not in('holder','coholder','authorized') then raise exception 'Rol no válido'; end if;
  u:=plone27_client_user(p_client,p_external);
  insert into plone27_account_members(account_id,user_id,role) values(p_account,u,p_role)
    on conflict(account_id,user_id) do update set role=excluded.role;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(null,'client_link','account',p_account::text,jsonb_build_object('cliente',p_client,'usuario',u,'rol',p_role));
  return u; end $$;

-- Orígenes de navegador: los administra personal, no el banco
create or replace function plone27_client_origin_add(p_client uuid,p_origin text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column begin
  insert into plone27_client_origins(client_id,origin) values(p_client,p_origin) on conflict do nothing;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'client_origin_add','client',p_client::text,jsonb_build_object('origen',p_origin));
end $$;

-- Seguridad: las tablas nuevas no se leen desde el panel (contienen hashes y secretos de sesión)
do $$ declare t text; f text; v text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks','plone27_user_sessions','plone27_api_nonces') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
end $$;

-- ==================== 0017_plone27_dip_identificador.sql ====================
-- Placeta One · 0017 · El DIP es el identificador del usuario.
-- Una persona = un DIP = un usuario de la plataforma en todas las entidades.
-- Cada entidad solo ve sus propias cuentas (la sesión queda ligada a la entidad del cliente).
-- Requiere 0016. Idempotente.

-- Cambian firmas y columnas devueltas: se eliminan antes de recrear (PostgreSQL no permite cambiar parámetros con OR REPLACE).
drop function if exists plone27_session_open(uuid,text,text,text[],int);
drop function if exists plone27_session_check(text);
drop function if exists plone27_user_can(uuid,uuid,boolean);
drop function if exists plone27_user_accounts(uuid);
drop function if exists plone27_user_transactions(uuid,uuid,bigint,int);
drop function if exists plone27_user_receipts(uuid,uuid);
drop function if exists plone27_user_transfer(text,uuid,text,text,numeric,text);
drop function if exists plone27_client_link_account(uuid,text,uuid,text);
drop function if exists plone27_client_user(uuid,text);
drop table if exists plone27_client_users;

-- Persona: un DIP normalizado. Es dato personal: la tabla no es legible desde el panel.
create table if not exists plone27_personas(
  id uuid primary key default gen_random_uuid(),
  dip text not null unique check(dip ~ '^[A-Z0-9]{5,20}$'),
  created_at timestamptz not null default now());

-- Sal para el hash de auditoría (aleatoria, se genera una vez por instalación)
insert into plone27_config(key,value) values('dip_pepper', replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''))
  on conflict(key) do nothing;

create or replace function plone27_normalizar_dip(p_dip text) returns text
language sql immutable as $$ select upper(regexp_replace(coalesce(p_dip,''),'[^A-Za-z0-9]','','g')) $$;

-- Hash con sal del DIP: es lo único que puede aparecer en auditoría o registros
create or replace function plone27_dip_hash(p_dip text) returns text
language sql stable security definer set search_path=public as $$
  select encode(sha256(convert_to((select value from plone27_config where key='dip_pepper')||':'||plone27_normalizar_dip(p_dip),'utf8')),'hex') $$;

-- Devuelve el identificador de la persona para un DIP (lo crea la primera vez)
create or replace function plone27_persona(p_dip text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d text:=plone27_normalizar_dip(p_dip); pid uuid; begin
  if d !~ '^[A-Z0-9]{5,20}$' then raise exception 'DIP no válido'; end if;
  insert into plone27_personas(dip) values(d) on conflict(dip) do nothing;
  select p.id into pid from plone27_personas p where p.dip=d;
  return pid; end $$;

create or replace function plone27_session_open(p_client uuid,p_dip text,p_hash text,p_scopes text[],p_ttl int) returns timestamptz
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u uuid; exp timestamptz; begin
  if p_ttl<1 or p_ttl>60 then raise exception 'TTL fuera de rango (1 a 60 minutos)'; end if;
  u:=plone27_persona(p_dip);
  exp:=now()+make_interval(mins=>p_ttl);
  insert into plone27_user_sessions(client_id,platform_user_id,token_hash,scopes,expires_at) values(p_client,u,p_hash,p_scopes,exp);
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'session_open','client',p_client::text,jsonb_build_object('persona',u,'dip_hash',plone27_dip_hash(p_dip),'scopes',p_scopes,'minutos',p_ttl));
  return exp; end $$;

-- Valida un token y devuelve la entidad de la sesión (el usuario solo ve cuentas de esa entidad)
create or replace function plone27_session_check(p_hash text) returns table(client_id uuid,bank_id uuid,user_id uuid,scopes text[],rate_limit int)
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select s.client_id,c.bank_id,s.platform_user_id,s.scopes,c.rate_limit
    from plone27_user_sessions s join plone27_api_clients c on c.id=s.client_id
    where s.token_hash=p_hash and s.revoked_at is null and s.expires_at>now() and c.active;
end $$;

-- Autorización: la cuenta es del usuario, es de la entidad de la sesión y, si se pide, puede escribir
create or replace function plone27_user_can(p_user uuid,p_account uuid,p_write boolean,p_bank uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    where m.account_id=p_account and m.user_id=p_user and a.status='active' and a.bank_id=p_bank
      and (not p_write or m.role in('holder','coholder'))) $$;

create or replace function plone27_user_accounts(p_user uuid,p_bank uuid) returns table(id uuid,iban text,nombre text,tipo text,rol text,saldo numeric,disponible numeric)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query select a.id,a.iban,a.name,a.kind,m.role,b.booked,b.booked-b.reserved
    from plone27_account_members m join plone27_accounts a on a.id=m.account_id
    join plone27_account_balances b on b.account_id=a.id
    where m.user_id=p_user and a.status='active' and a.bank_id=p_bank order by a.created_at;
end $$;

create or replace function plone27_user_transactions(p_user uuid,p_account uuid,p_antes bigint,p_limite int,p_bank uuid)
returns table(id bigint,fecha timestamptz,sentido text,importe numeric,tipo text,memo text)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select e.id,e.created_at,e.direction,e.amount,t.kind,t.memo
    from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.account_id=p_account and (p_antes is null or e.id<p_antes)
    order by e.id desc limit least(greatest(p_limite,1),100);
end $$;

create or replace function plone27_user_receipts(p_user uuid,p_account uuid,p_bank uuid)
returns table(ref text,impuesto text,base numeric,importe numeric,pagado numeric,estado text,vence date,creado timestamptz)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  if not plone27_user_can(p_user,p_account,false,p_bank) then raise exception 'Cuenta no accesible'; end if;
  return query select r.ref,ru.code,r.base,r.amount,r.paid_amount,r.status,r.due_date,r.created_at
    from plone27_tax_receipts r join plone27_tax_rule_versions v on v.id=r.rule_version_id
    join plone27_tax_rules ru on ru.id=v.rule_id
    where r.account_id=p_account order by r.created_at desc limit 200;
end $$;

create or replace function plone27_user_transfer(p_key text,p_user uuid,p_from_iban text,p_to_iban text,p_amount numeric,p_memo text,p_bank uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; t uuid; begin
  select id into f from plone27_accounts where iban=p_from_iban;
  if f is null or not plone27_user_can(p_user,f,true,p_bank) then raise exception 'Cuenta de origen no accesible'; end if;
  select id into t from plone27_accounts where iban=p_to_iban and status='active';
  if t is null then raise exception 'Cuenta destino no válida'; end if;
  if t=f then raise exception 'Origen y destino no pueden coincidir'; end if;
  return plone27_transfer(p_key,f,t,p_amount,coalesce(p_memo,'Transferencia'),p_user);
end $$;

-- Alta de un usuario (DIP) en una cuenta de la entidad del cliente
create or replace function plone27_client_link_account(p_client uuid,p_dip text,p_account uuid,p_role text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare u uuid; bk uuid; begin
  select bank_id into bk from plone27_api_clients where id=p_client;
  if not exists(select 1 from plone27_accounts where id=p_account and bank_id=bk) then raise exception 'La cuenta no pertenece a la entidad del cliente'; end if;
  if p_role not in('holder','coholder','authorized') then raise exception 'Rol no válido'; end if;
  u:=plone27_persona(p_dip);
  insert into plone27_account_members(account_id,user_id,role) values(p_account,u,p_role)
    on conflict(account_id,user_id) do update set role=excluded.role;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(null,'client_link','account',p_account::text,jsonb_build_object('cliente',p_client,'dip_hash',plone27_dip_hash(p_dip),'rol',p_role));
  return u; end $$;

-- Seguridad: el DIP y los tokens no se leen desde el panel
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

-- Comprobación final: las funciones de la API de bancos existen
do $$ declare falta text := ''; f text; begin
  foreach f in array array['plone27_session_open','plone27_session_check','plone27_user_accounts','plone27_user_transfer','plone27_client_link_account','plone27_previsiones','plone27_kpis'] loop
    if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=f) then falta := falta || ' ' || f; end if;
  end loop;
  if falta <> '' then raise exception 'Faltan funciones tras la actualización:%', falta; end if;
  raise notice 'Actualización 0015–0017 aplicada correctamente.';
end $$;

commit;
