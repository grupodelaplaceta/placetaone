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
language plpgsql security definer set search_path=public as $$ begin
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
