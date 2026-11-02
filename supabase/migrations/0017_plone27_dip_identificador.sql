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
