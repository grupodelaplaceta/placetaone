-- =====================================================================================================
-- PLACETA ONE · ACTUALIZACIÓN 0022 · Catálogo de diseños de tarjeta
-- REQUISITO: la base tiene aplicadas las migraciones 0001 a 0021.
-- AÑADE: código comercial, banco, rareza, imagen y GIF, stock, publicación en API, compra con stock,
--        catálogo para bancos y para usuarios.
-- Transacción única; reejecutable.
-- =====================================================================================================

begin;
-- Placeta One · 0022 · Catálogo de diseños de tarjeta: código, banco, rareza, imagen/GIF, stock y publicación en API.
-- Requiere 0021. Idempotente.

create sequence if not exists plone27_design_codigo_seq;
alter table plone27_card_designs add column if not exists codigo text unique
  default ('DIS-'||lpad(nextval('plone27_design_codigo_seq')::text,5,'0'));   -- identificador comercial estable
alter table plone27_card_designs add column if not exists bank_id uuid references plone27_banks;   -- null = catálogo general
alter table plone27_card_designs add column if not exists rareza text not null default 'comun'
  check(rareza in('comun','rara','epica','legendaria'));
alter table plone27_card_designs add column if not exists descripcion text check(length(descripcion)<=500);
alter table plone27_card_designs add column if not exists imagen_url text check(imagen_url is null or imagen_url ~ '^https://[^\s]+$');
alter table plone27_card_designs add column if not exists animacion_url text check(animacion_url is null or animacion_url ~ '^https://[^\s]+$');
alter table plone27_card_designs add column if not exists stock int check(stock is null or stock>=0);   -- null = ilimitado
alter table plone27_card_designs add column if not exists vendidos int not null default 0 check(vendidos>=0);
alter table plone27_card_designs add column if not exists publicado_api boolean not null default false;

-- Restricción de stock. El generador de instalación la hace idempotente por sí mismo: no envolver en DO.
do $$ begin alter table plone27_card_designs add constraint plone27_design_stock_ck check(stock is null or vendidos<=stock) not valid; exception when duplicate_object then null; end $$;

-- Compra de un diseño: comprueba estado, banco y stock; descuenta una unidad solo en la primera compra
-- (un reintento con la misma clave no vuelve a restar).
create or replace function plone27_design_buy(p_key text,p_design uuid,p_account uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare d plone27_card_designs; tx uuid; t numeric; ab uuid; ya boolean; ins int; begin
  select * into d from plone27_card_designs where id=p_design for update;
  if d.id is null then raise exception 'Diseño no encontrado'; end if;
  if d.status<>'approved' or not d.publicado_api then raise exception 'Diseño no disponible'; end if;
  select a.bank_id into ab from plone27_accounts a where a.id=p_account;
  if d.bank_id is not null and d.bank_id<>ab then raise exception 'Diseño no disponible en tu entidad'; end if;
  select exists(select 1 from plone27_design_purchases p where p.design_id=p_design and p.account_id=p_account) into ya;
  if not ya and d.stock is not null and d.vendidos>=d.stock then raise exception 'Sin stock'; end if;
  t:=d.price+d.license_fee;
  if t>0 then tx:=plone27_transfer(p_key,p_account,d.revenue_account,t,'Diseño '||d.name,p_actor); end if;
  insert into plone27_design_purchases(design_id,account_id,tx) values(p_design,p_account,tx) on conflict do nothing;
  get diagnostics ins = row_count;
  if ins>0 then update plone27_card_designs set vendidos=vendidos+1 where id=p_design; end if;
  return tx;
end $$;

-- Catálogo para un banco: diseños aprobados, publicados en API, de su entidad o generales, con stock disponible
create or replace function plone27_catalogo_disenos(p_bank uuid)
returns table(codigo text,nombre text,nivel text,rareza text,precio numeric,licencia numeric,descripcion text,
              imagen_url text,animacion_url text,stock_disponible int,vendidos int)
language sql stable security definer set search_path=public as $$
  select d.codigo,d.name,d.tier,d.rareza,d.price,d.license_fee,d.descripcion,d.imagen_url,d.animacion_url,
         case when d.stock is null then null else (d.stock-d.vendidos)::int end,
         d.vendidos
  from plone27_card_designs d
  where d.status='approved' and d.publicado_api and (d.bank_id is null or d.bank_id=p_bank)
    and (d.stock is null or d.vendidos<d.stock)
  order by d.name
$$;

-- Catálogo para un usuario concreto: añade si ya tiene el diseño en alguna de sus cuentas
create or replace function plone27_user_catalogo(p_user uuid,p_bank uuid)
returns table(codigo text,nombre text,nivel text,rareza text,precio numeric,licencia numeric,descripcion text,
              imagen_url text,animacion_url text,stock_disponible int,ya_adquirido boolean)
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
begin
  return query
    select c.codigo,c.nombre,c.nivel,c.rareza,c.precio,c.licencia,c.descripcion,c.imagen_url,c.animacion_url,c.stock_disponible,
           exists(select 1 from plone27_design_purchases p
                  join plone27_account_members m on m.account_id=p.account_id
                  join plone27_card_designs dd on dd.id=p.design_id
                  where dd.codigo=c.codigo and m.user_id=p_user)
    from plone27_catalogo_disenos(p_bank) c;
end $$;

-- Compra de un diseño por un usuario, desde una cuenta propia con permiso de escritura
create or replace function plone27_user_diseno_comprar(p_user uuid,p_bank uuid,p_codigo text,p_iban text,p_key text) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare acc uuid; did uuid; begin
  select a.id into acc from plone27_accounts a where a.iban=p_iban and a.bank_id=p_bank;
  if acc is null or not plone27_user_can(p_user,acc,true,p_bank) then raise exception 'Cuenta no accesible'; end if;
  select d.id into did from plone27_card_designs d where d.codigo=p_codigo and (d.bank_id is null or d.bank_id=p_bank);
  if did is null then raise exception 'Diseño no encontrado'; end if;
  return plone27_design_buy(p_key, did, acc, p_user);
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


do $$ begin raise notice 'Actualización 0022 aplicada correctamente.'; end $$;

commit;
