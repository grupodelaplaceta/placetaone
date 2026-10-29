-- Placeta One · numeración e identificadores, multibanco, API clients. Generado siempre en servidor.
create table plone27_numbering_formats(kind text not null, version int not null, prefix text not null check(prefix ~ '^PL27-[A-Z]{3}-$'),
 year_scoped boolean not null, width int not null check(width between 4 and 15), status text not null default 'draft' check(status in('draft','published')),
 reason text, author uuid, approved_by uuid, valid_from date not null default current_date, primary key(kind,version));
create table plone27_counters(kind text not null, scope text not null, last bigint not null, primary key(kind,scope));
create table plone27_issued_ids(identifier text primary key, kind text not null, at timestamptz default now());  -- nunca se reutilizan ni se borran
create trigger t_ids_ro before update or delete on plone27_issued_ids for each row execute function plone27_immutable();
insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,status,reason) values
('TAR',1,'PL27-TAR-',false,8,'published','inicial'),('TRF',1,'PL27-TRF-',false,12,'published','inicial'),('OPE',1,'PL27-OPE-',false,12,'published','inicial'),('AUT',1,'PL27-AUT-',false,8,'published','inicial'),
('REC',1,'PL27-REC-',true,6,'published','inicial'),('LIQ',1,'PL27-LIQ-',true,6,'published','inicial'),('REG',1,'PL27-REG-',true,6,'published','inicial'),('SUB',1,'PL27-SUB-',true,6,'published','inicial'),
('BON',1,'PL27-BON-',true,6,'published','inicial'),('JUS',1,'PL27-JUS-',true,6,'published','inicial'),('REE',1,'PL27-REE-',true,6,'published','inicial'),('FAC',1,'PL27-FAC-',true,6,'published','inicial'),
('DEU',1,'PL27-DEU-',true,6,'published','inicial'),('INC',1,'PL27-INC-',true,6,'published','inicial');

create function plone27_next_num(p_kind text,p_scope text,p_max bigint) returns bigint language plpgsql security definer set search_path=public as $$ declare n bigint; begin
 insert into plone27_counters values(p_kind,p_scope,1) on conflict(kind,scope) do update set last=plone27_counters.last+1 returning last into n;
 if n>p_max then raise exception 'Capacidad agotada (% / %)',p_kind,p_scope; end if; return n; end $$;
create function plone27_next_id(p_kind text) returns text language plpgsql security definer set search_path=public as $$ declare f plone27_numbering_formats; sc text; n bigint; id text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and status='published' and valid_from<=current_date order by version desc limit 1;
 if not found then raise exception 'Formato % sin publicar',p_kind; end if;
 sc:=case when f.year_scoped then extract(year from current_date)::text else 'global' end;
 n:=plone27_next_num(p_kind||':v'||f.version,sc,(power(10,f.width)-1)::bigint);
 id:=f.prefix||case when f.year_scoped then sc||'-' else '' end||lpad(n::text,f.width,'0');
 insert into plone27_issued_ids(identifier,kind) values(id,p_kind); return id; end $$;

-- Configuración versionada: propuesta → simulación → publicación aprobada (no altera identificadores históricos)
create function plone27_numbering_propose(p_kind text,p_prefix text,p_year boolean,p_width int,p_reason text,p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare v int; begin
 select coalesce(max(version),0)+1 into v from plone27_numbering_formats where kind=p_kind;
 insert into plone27_numbering_formats(kind,version,prefix,year_scoped,width,reason,author) values(p_kind,v,p_prefix,p_year,p_width,p_reason,p_actor); return v; end $$;
create function plone27_numbering_simulate(p_kind text,p_version int,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare f plone27_numbering_formats; s text; begin
 select * into f from plone27_numbering_formats where kind=p_kind and version=p_version;
 s:=f.prefix||case when f.year_scoped then extract(year from current_date)||'-' else '' end||lpad('1',f.width,'0');
 return jsonb_build_object('sample',s,'collides',exists(select 1 from plone27_issued_ids where identifier=s),'capacity',power(10,f.width)-1); end $$;
create function plone27_numbering_publish(p_kind text,p_version int,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ begin
 if plone27_numbering_simulate(p_kind,p_version,p_actor)->>'collides'='true' then raise exception 'Colisión de formato'; end if;
 update plone27_numbering_formats set status='published',approved_by=p_actor,valid_from=current_date where kind=p_kind and version=p_version and status='draft';
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'numbering_publish',p_kind,p_version::text); end $$;

-- Referencias automáticas e inmutables en documentos
create function plone27_set_ref() returns trigger language plpgsql security definer set search_path=public as $$ declare k text:=tg_argv[0]; begin
 if tg_table_name='plone27_grants' then select case p.kind when 'bono' then 'BON' else 'SUB' end into k from plone27_grant_programs p where p.id=new.program_id; end if;
 if new.ref is null then new.ref:=plone27_next_id(k); end if; return new; end $$;
create function plone27_ref_lock() returns trigger language plpgsql as $$ begin
 if new.ref is distinct from old.ref then raise exception 'Referencia inmutable'; end if; return new; end $$;
do $$ declare x text[]; begin
 foreach x slice 1 in array array[['plone27_tax_receipts','REC'],['plone27_tax_adjustments','REG'],['plone27_grants','SUB'],['plone27_justifications','JUS'],['plone27_incidents','INC'],['plone27_debts','DEU'],['plone27_approvals','AUT']] loop
  execute format('alter table %I add column ref text unique',x[1]);
  execute format('create trigger t_ref before insert on %I for each row execute function plone27_set_ref(%L)',x[1],x[2]);
  execute format('create trigger t_ref_lock before update on %I for each row execute function plone27_ref_lock()',x[1]); end loop; end $$;
alter table plone27_transactions add column ref text unique, add column transfer_ref text unique;
create function plone27_tx_refs() returns trigger language plpgsql security definer set search_path=public as $$ begin
 new.ref:=plone27_next_id('OPE'); if new.kind='transfer' then new.transfer_ref:=plone27_next_id('TRF'); end if; return new; end $$;
create trigger t_tx_refs before insert on plone27_transactions for each row execute function plone27_tx_refs();
create trigger t_tx_ref_lock before update on plone27_transactions for each row execute function plone27_ref_lock();
alter table plone27_justifications add column reimb_ref text unique;
create function plone27_reimb_ref() returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.status='paid' and new.reimb_ref is null then new.reimb_ref:=plone27_next_id('REE'); end if; return new; end $$;
create trigger t_reimb before update on plone27_justifications for each row execute function plone27_reimb_ref();

-- Entidades y cuentas PZ-EEEE-CCCC (servidor únicamente, inmutables)
alter table plone27_banks add constraint banks_code4 check(code ~ '^[0-9]{4}$') not valid;
insert into plone27_banks(code,name,status) values('0000','Placeta Administración','active');   -- entidad reservada (cuentas de sistema)
alter table plone27_accounts add column iban text unique;
create function plone27_iban_guard() returns trigger language plpgsql as $$ begin
 if tg_op='INSERT' then
  if new.iban is null or new.iban !~ '^PZ-[0-9]{4}-[0-9]{4}$' or substr(new.iban,4,4) is distinct from (select code from plone27_banks where id=new.bank_id) then raise exception 'IBAN solo generado por servidor'; end if;
 elsif new.iban is distinct from old.iban or new.bank_id is distinct from old.bank_id then raise exception 'IBAN inmutable'; end if; return new; end $$;
create trigger t_iban before insert or update on plone27_accounts for each row execute function plone27_iban_guard();
create function plone27_open_bank(p_name text,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare c text; id uuid; begin
 c:=lpad(plone27_next_num('BANK','global',9999)::text,4,'0'); insert into plone27_banks(code,name) values(c,p_name) returning plone27_banks.id into id; return jsonb_build_object('id',id,'code',c); end $$;
create function plone27_open_account(p_bank uuid,p_kind text,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare vc text; i text; id uuid; begin
 select b.code into vc from plone27_banks b where b.id=p_bank and b.status='active'; if vc is null then raise exception 'Entidad inexistente o no activa'; end if;
 i:='PZ-'||vc||'-'||lpad(plone27_next_num('ACC',vc,9999)::text,4,'0');
 insert into plone27_accounts(bank_id,kind,name,owner_user,iban,allow_negative) values(p_bank,p_kind,p_name,p_owner,i,p_kind='system') returning plone27_accounts.id into id;
 insert into plone27_audit_log(actor,action,entity,entity_id) values(p_actor,'open_account','account',i); return jsonb_build_object('id',id,'iban',i); end $$;

-- Tarjetas: id administrativo PL27-TAR; número visible solo en pruebas; sin PAN/CVV almacenados
alter table plone27_cards drop constraint plone27_cards_status_check, add check(status in('active','suspended','blocked','closed')),
 add column card_ref text unique, add column is_test boolean not null default false, add column expires date, add column last4 text, add column pan_hash text unique;
create function plone27_issue_card(p_account uuid,p_kind text,p_design uuid,p_limit numeric,p_test boolean,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare r text; num text; cid uuid; begin
 if not exists(select 1 from plone27_accounts where id=p_account and status='active') then raise exception 'Cuenta no activa'; end if;
 if p_design is not null and not exists(select 1 from plone27_design_purchases where design_id=p_design and account_id=p_account) then raise exception 'Diseño no adquirido'; end if;
 r:=plone27_next_id('TAR');
 if p_test then num:=lpad(floor(random()*10000000000000000)::bigint::text,16,'0'); end if;
 insert into plone27_cards(account_id,kind,design_id,credit_limit,card_ref,is_test,expires,last4,pan_hash)
  values(p_account,p_kind,p_design,p_limit,r,p_test,current_date+interval '5 years',right(num,4),encode(sha256(convert_to(coalesce(num,r),'utf8')),'hex')) returning plone27_cards.id into cid;
 return jsonb_build_object('id',cid,'card_ref',r,'test_number',regexp_replace(num,'(\d{4})(?=\d)','\1 ','g')); end $$;  -- el número de prueba se devuelve una sola vez
create function plone27_card_set_status(p_card uuid,p_to text,p_actor uuid) returns void language plpgsql security definer set search_path=public as $$ declare o text; begin
 select status into o from plone27_cards where id=p_card for update; if o='closed' then raise exception 'Tarjeta cancelada'; end if;
 update plone27_cards set status=p_to where id=p_card; insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'card_status','card',p_card::text,to_jsonb(p_to)); end $$;
create function plone27_card_renew(p_card uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$ declare c plone27_cards; begin
 select * into c from plone27_cards where id=p_card; perform plone27_card_set_status(p_card,'closed',p_actor);
 return plone27_issue_card(c.account_id,c.kind,c.design_id,c.credit_limit,c.is_test,p_actor); end $$;

-- Multibanco: clientes API por entidad con scopes y límite de uso
create table plone27_api_clients(id uuid primary key default gen_random_uuid(), bank_id uuid not null references plone27_banks, name text not null,
 key_hash text unique not null, scopes text[] not null default '{}', rate_limit int not null default 60, active boolean not null default true, created_at timestamptz default now());
create table plone27_api_usage(client_id uuid references plone27_api_clients, minute timestamptz, hits int not null default 0, primary key(client_id,minute));
create function plone27_rate_hit(p_client uuid) returns int language sql security definer set search_path=public as $$
 insert into plone27_api_usage values(p_client,date_trunc('minute',now()),1) on conflict(client_id,minute) do update set hits=plone27_api_usage.hits+1 returning hits $$;

do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t<>'plone27_api_clients' and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname<>'plone27_has_role' loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;
