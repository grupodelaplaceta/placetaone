-- Productos financieros por entidad: cuentas (personal, empresa, compartida, Junior), tarjetas, crédito interno y servicios
create table plone27_products(id uuid primary key default gen_random_uuid(), code text unique not null, bank_id uuid not null references plone27_banks,
 kind text not null check(kind in('account_personal','account_business','account_shared','account_junior','card_digital','card_physical','card_credit','internal_credit','service')),
 name text not null, description text, status text not null default 'draft' check(status in('draft','active','retired')),
 daily_limit numeric(18,2), credit_limit numeric(18,2), monthly_fee numeric(18,2) not null default 0 check(monthly_fee>=0), fee_account uuid references plone27_accounts,
 interest_rate numeric(9,4) not null default 0, min_age int, requires_guardian boolean not null default false, valid_from date, valid_to date,
 terms jsonb not null default '{}', approved_by uuid, created_by uuid, created_at timestamptz default now());
alter table plone27_accounts add column product_id uuid references plone27_products;
create function plone27_product_guard() returns trigger language plpgsql as $$ begin
 if new.status is distinct from old.status then
  if (old.status,new.status) not in(('draft','active'),('active','retired'),('draft','retired')) then raise exception 'Transición de producto % → % no permitida',old.status,new.status; end if;
  if new.status='active' and new.approved_by is null then raise exception 'Activar un producto requiere aprobación registrada'; end if; end if; return new; end $$;
create trigger t_product_guard before update on plone27_products for each row execute function plone27_product_guard();
create function plone27_open_account_p(p_product uuid,p_name text,p_owner uuid,p_actor uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare p plone27_products; k text; r jsonb; begin
 select * into p from plone27_products where id=p_product and status='active' and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
 if p.id is null then raise exception 'Producto no disponible'; end if; if p.kind not like 'account\_%' then raise exception 'No es un producto de cuenta'; end if;
 k:=case p.kind when 'account_personal' then 'personal' when 'account_business' then 'business' when 'account_shared' then 'shared' else 'junior' end;
 r:=plone27_open_account(p.bank_id,k,p_name,p_owner,p_actor);
 update plone27_accounts set product_id=p_product,daily_limit=coalesce(p.daily_limit,daily_limit) where id=(r->>'id')::uuid; return r; end $$;
create function plone27_charge_product_fees(p_actor uuid) returns int language plpgsql security definer set search_path=public as $$ declare n int:=0; a record; begin
 for a in select ac.id,p.monthly_fee fee,p.fee_account from plone27_accounts ac join plone27_products p on p.id=ac.product_id where ac.status='active' and p.monthly_fee>0 and p.fee_account is not null loop
  begin perform plone27_transfer('pfee:'||a.id||':'||to_char(now(),'YYYY-MM'),a.id,a.fee_account,a.fee,'Cuota de producto',p_actor); n:=n+1;
  exception when others then insert into plone27_incidents(kind,detail) values('product_fee_failed',jsonb_build_object('account',a.id,'err',sqlerrm)); end; end loop; return n; end $$;
do $$ declare t text; f text; begin
 for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
  execute format('alter table %I enable row level security',t);
  if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
   execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if; end loop;
 for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
  execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop; end $$;
