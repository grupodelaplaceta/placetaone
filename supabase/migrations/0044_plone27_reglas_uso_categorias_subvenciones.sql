-- Placeta One · 0044 · Reglas de uso de RBU y de subvenciones (tipos de cuenta, comercios y categorías),
-- categorías de comercio (Placeta), y API de programas, concesiones, justificaciones y reglas para bancos.
-- Requiere 0043. Idempotente. NO ejecutado en PostgreSQL: probar antes de producción.

-- ---------- Categorías de comercio (las asigna Placeta) ----------
create table if not exists plone27_categorias(
  codigo text primary key check(codigo ~ '^[a-z_]{3,30}$'),
  nombre text not null check(length(nombre) between 3 and 60),
  activa boolean not null default true);
insert into plone27_categorias(codigo,nombre) values
  ('alimentacion','Alimentación'),('salud','Salud'),('educacion','Educación'),('transporte','Transporte'),
  ('vivienda','Vivienda'),('ocio','Ocio'),('otros','Otros')
on conflict(codigo) do nothing;

alter table plone27_accounts add column if not exists categoria text references plone27_categorias(codigo);
alter table plone27_accounts drop constraint if exists plone27_accounts_categoria_business;
alter table plone27_accounts add constraint plone27_accounts_categoria_business check(categoria is null or kind='business');

-- ---------- Reglas de destino (RBU por bono, o por programa de subvención) ----------
create table if not exists plone27_politicas_destino(
  id uuid primary key default gen_random_uuid(),
  bank_id uuid not null references plone27_banks,
  ambito text not null check(ambito in('rbu','programa')),
  programa_id uuid references plone27_grant_programs,
  tipos_destino text[] not null default '{}',
  comercios uuid[] not null default '{}',
  categorias text[] not null default '{}',
  activa boolean not null default true,
  creada timestamptz not null default now(),
  check((ambito='programa' and programa_id is not null) or (ambito='rbu' and programa_id is null)),
  check(tipos_destino <@ array['personal','business','shared','junior','system']::text[]));
create unique index if not exists plone27_politica_rbu_ux on plone27_politicas_destino(bank_id) where ambito='rbu' and activa;
create unique index if not exists plone27_politica_programa_ux on plone27_politicas_destino(programa_id) where ambito='programa' and activa;

-- ¿Puede esta regla pagar a esta cuenta? Cada filtro configurado debe cumplirse. Un filtro vacío no restringe.
create or replace function plone27_destino_permitido(p_politica uuid,p_destino uuid) returns boolean
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare p plone27_politicas_destino; c plone27_accounts; begin
  select * into p from plone27_politicas_destino where id=p_politica;
  select * into c from plone27_accounts where id=p_destino;
  if p.id is null or c.id is null then return false; end if;
  if cardinality(p.tipos_destino)>0 and not(c.kind=any(p.tipos_destino)) then return false; end if;
  if cardinality(p.comercios)>0 and not(c.id=any(p.comercios)) then return false; end if;
  if cardinality(p.categorias)>0 and not(coalesce(c.categoria,'')=any(p.categorias)) then return false; end if;
  return true; end $$;

-- RBU: cada cargo de tarjeta prepago se comprueba contra la regla RBU del banco de la tarjeta
create or replace function plone27_trg_rbu_destino() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_cards; bk uuid; pol uuid; begin
  select cd.* into c from plone27_cards cd where cd.id=new.card_id;
  if c.id is null or c.kind<>'prepago' then return new; end if;
  select a.bank_id into bk from plone27_accounts a where a.id=c.account_id;
  select p.id into pol from plone27_politicas_destino p where p.bank_id=bk and p.ambito='rbu' and p.activa;
  if pol is null then return new; end if;
  if not plone27_destino_permitido(pol,new.merchant_account) then
    raise exception 'Esta tarjeta RBU no puede pagar en ese comercio';
  end if;
  return new; end $$;
drop trigger if exists trg_rbu_destino on plone27_card_charges;
create trigger trg_rbu_destino before insert on plone27_card_charges
  for each row execute function plone27_trg_rbu_destino();

-- Subvención: la justificación debe ser un gasto de la cuenta beneficiaria cuyo destino cumple la regla del programa
create or replace function plone27_trg_justificacion_destino() returns trigger
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; pol uuid; dest uuid; begin
  select * into g from plone27_grants where id=new.grant_id;
  select p.id into pol from plone27_politicas_destino p where p.programa_id=g.program_id and p.activa;
  if pol is null then return new; end if;
  if not exists(select 1 from plone27_ledger_entries l where l.transaction_id=new.transaction_id
                and l.account_id=g.beneficiary_account and l.direction='debit') then
    raise exception 'La transacción no es un gasto de la cuenta beneficiaria';
  end if;
  select l.account_id into dest from plone27_ledger_entries l
    where l.transaction_id=new.transaction_id and l.direction='credit' and l.account_id<>g.beneficiary_account limit 1;
  if dest is null then raise exception 'La transacción no tiene un destino que justificar'; end if;
  if not plone27_destino_permitido(pol,dest) then
    raise exception 'El destino de ese gasto no está permitido por la convocatoria';
  end if;
  return new; end $$;
drop trigger if exists trg_justificacion_destino on plone27_justifications;
create trigger trg_justificacion_destino before insert on plone27_justifications
  for each row execute function plone27_trg_justificacion_destino();

-- ---------- Administración de Placeta: categorías y categoría de cada comercio ----------
create or replace function plone27_categoria_set(p_codigo text,p_nombre text,p_activa boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  if p_codigo is null or p_codigo !~ '^[a-z_]{3,30}$' then raise exception 'Código de categoría no válido'; end if;
  insert into plone27_categorias(codigo,nombre,activa) values(p_codigo,p_nombre,coalesce(p_activa,true))
    on conflict(codigo) do update set nombre=excluded.nombre, activa=excluded.activa;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'categoria_set','categoria',p_codigo,jsonb_build_object('activa',p_activa));
end $$;

create or replace function plone27_cuenta_categoria_set(p_iban text,p_categoria text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  if p_categoria is not null and not exists(select 1 from plone27_categorias c where c.codigo=p_categoria and c.activa) then
    raise exception 'Categoría no válida';
  end if;
  with x as(update plone27_accounts set categoria=p_categoria where iban=p_iban and kind='business' returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Solo se pueden categorizar cuentas de comercio (empresa)'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'comercio_categoria','cuenta',p_iban,jsonb_build_object('categoria',p_categoria));
end $$;

-- ---------- API de banco: catálogos ----------
create or replace function plone27_bk_categorias() returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.codigo),'[]'::jsonb) from (
    select c.codigo, c.nombre from plone27_categorias c where c.activa) x $$;

-- Directorio de comercios: cuentas de empresa activas, sin saldos
create or replace function plone27_bk_comercios() returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.nombre),'[]'::jsonb) from (
    select a.iban, a.name as nombre, a.categoria, b.code as banco
    from plone27_accounts a join plone27_banks b on b.id=a.bank_id
    where a.kind='business' and a.status='active') x $$;

-- ---------- API de banco: programas, concesiones y justificaciones ----------
create or replace function plone27_bk_programas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.nombre),'[]'::jsonb) from (
    select gp.id, gp.name as nombre, gp.kind as tipo, gp.budget as presupuesto, a.iban as cuenta_fondos,
      (select count(*) from plone27_grants g where g.program_id=gp.id) as concesiones
    from plone27_grant_programs gp join plone27_accounts a on a.id=gp.funding_account
    where a.bank_id=p_bank) x $$;

create or replace function plone27_bk_programa_crear(p_bank uuid,p_name text,p_kind text,p_budget numeric,p_funding_iban text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare f uuid; pid uuid; begin
  if p_kind not in('subvencion','bono') then raise exception 'Tipo no válido (subvencion o bono)'; end if;
  if coalesce(length(p_name),0)<3 then raise exception 'Nombre demasiado corto'; end if;
  if p_budget is null or p_budget<=0 then raise exception 'Presupuesto no válido'; end if;
  select a.id into f from plone27_accounts a where a.iban=p_funding_iban and a.bank_id=p_bank;
  if f is null then raise exception 'La cuenta de fondos debe ser de tu entidad'; end if;
  insert into plone27_grant_programs(name,kind,budget,funding_account) values(p_name,p_kind,p_budget,f)
    returning plone27_grant_programs.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'programa_crear','programa',pid::text,jsonb_build_object('tipo',p_kind,'presupuesto',p_budget));
  return pid; end $$;

create or replace function plone27_bk_concesiones(p_bank uuid,p_program uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.programa, x.beneficiario),'[]'::jsonb) from (
    select g.id, g.program_id, gp.name as programa, b.iban as beneficiario,
      g.granted as concedido, g.approved as aprobado, g.paid as pagado
    from plone27_grants g join plone27_grant_programs gp on gp.id=g.program_id
    join plone27_accounts fa on fa.id=gp.funding_account
    join plone27_accounts b on b.id=g.beneficiary_account
    where fa.bank_id=p_bank and (p_program is null or g.program_id=p_program)) x $$;

create or replace function plone27_bk_concesion_crear(p_bank uuid,p_program uuid,p_beneficiary_iban text,p_granted numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare b uuid; gid uuid; begin
  if not exists(select 1 from plone27_grant_programs gp join plone27_accounts fa on fa.id=gp.funding_account
                where gp.id=p_program and fa.bank_id=p_bank) then raise exception 'Programa no encontrado en tu entidad'; end if;
  select a.id into b from plone27_accounts a where a.iban=p_beneficiary_iban and a.bank_id=p_bank and a.status='active';
  if b is null then raise exception 'El beneficiario debe ser una cuenta activa de tu entidad'; end if;
  if p_granted is null or p_granted<=0 then raise exception 'Importe concedido no válido'; end if;
  insert into plone27_grants(program_id,beneficiary_account,granted) values(p_program,b,p_granted)
    returning plone27_grants.id into gid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'concesion_crear','concesion',gid::text,jsonb_build_object('concedido',p_granted));
  return gid; end $$;

create or replace function plone27_bk_justificaciones(p_bank uuid,p_grant uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.id),'[]'::jsonb) from (
    select j.id, j.grant_id, j.transaction_id, j.invoice_ref as factura, j.amount as importe, j.status as estado, j.reimb_ref as reembolso
    from plone27_justifications j join plone27_grants g on g.id=j.grant_id
    join plone27_grant_programs gp on gp.id=g.program_id join plone27_accounts fa on fa.id=gp.funding_account
    where fa.bank_id=p_bank and (p_grant is null or j.grant_id=p_grant)) x $$;

create or replace function plone27_bk_justificar(p_bank uuid,p_grant uuid,p_tx uuid,p_invoice text,p_amount numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from plone27_grants g join plone27_grant_programs gp on gp.id=g.program_id
                join plone27_accounts fa on fa.id=gp.funding_account where g.id=p_grant and fa.bank_id=p_bank) then
    raise exception 'Concesión no encontrada en tu entidad';
  end if;
  return plone27_justify(p_grant,p_tx,p_invoice,p_amount,p_actor); end $$;

create or replace function plone27_bk_justificacion_pagar(p_bank uuid,p_just uuid,p_key text,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from plone27_justifications j join plone27_grants g on g.id=j.grant_id
                join plone27_grant_programs gp on gp.id=g.program_id join plone27_accounts fa on fa.id=gp.funding_account
                where j.id=p_just and fa.bank_id=p_bank) then
    raise exception 'Justificación no encontrada en tu entidad';
  end if;
  return plone27_reimburse(p_key,p_just,p_actor); end $$;

create or replace function plone27_bk_justificacion_rechazar(p_bank uuid,p_just uuid,p_motivo text,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare j plone27_justifications; begin
  select j.* into j from plone27_justifications j join plone27_grants g on g.id=j.grant_id
    join plone27_grant_programs gp on gp.id=g.program_id join plone27_accounts fa on fa.id=gp.funding_account
    where j.id=p_just and fa.bank_id=p_bank for update;
  if j.id is null then raise exception 'Justificación no encontrada en tu entidad'; end if;
  if j.status<>'pending' then raise exception 'Solo se rechazan justificaciones pendientes'; end if;
  update plone27_justifications set status='rejected' where id=p_just;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'justificacion_rechazada','justificacion',p_just::text,jsonb_build_object('motivo',p_motivo));
end $$;

-- ---------- API de banco: reglas de uso ----------
create or replace function plone27_bk_politicas(p_bank uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.creada desc),'[]'::jsonb) from (
    select p.id, p.ambito, p.programa_id, gp.name as programa, p.tipos_destino as tipos, p.comercios, p.categorias, p.activa, p.creada
    from plone27_politicas_destino p left join plone27_grant_programs gp on gp.id=p.programa_id
    where p.bank_id=p_bank) x $$;

create or replace function plone27_bk_politica_crear(p_bank uuid,p_ambito text,p_programa uuid,p_tipos text[],p_comercios uuid[],p_categorias text[],p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pid uuid; begin
  if p_ambito not in('rbu','programa') then raise exception 'Ámbito no válido'; end if;
  if p_ambito='programa' and not exists(select 1 from plone27_grant_programs gp join plone27_accounts fa on fa.id=gp.funding_account
     where gp.id=p_programa and fa.bank_id=p_bank) then raise exception 'Programa no encontrado en tu entidad'; end if;
  if p_ambito='rbu' then p_programa:=null; end if;
  if exists(select 1 from unnest(coalesce(p_categorias,'{}'::text[])) q where not exists(select 1 from plone27_categorias c where c.codigo=q and c.activa)) then
    raise exception 'Alguna categoría no existe';
  end if;
  if exists(select 1 from unnest(coalesce(p_comercios,'{}'::uuid[])) q where not exists(select 1 from plone27_accounts a where a.id=q and a.kind='business')) then
    raise exception 'Alguno de los comercios no es una cuenta de empresa';
  end if;
  if exists(select 1 from unnest(coalesce(p_tipos,'{}'::text[])) q where q not in('personal','business','shared','junior','system')) then
    raise exception 'Algún tipo de cuenta no existe';
  end if;
  -- una sola regla activa por ámbito: la nueva sustituye a la anterior
  update plone27_politicas_destino set activa=false where bank_id=p_bank and ambito=p_ambito and activa
    and (programa_id is not distinct from p_programa);
  insert into plone27_politicas_destino(bank_id,ambito,programa_id,tipos_destino,comercios,categorias)
    values(p_bank,p_ambito,p_programa,coalesce(p_tipos,'{}'),coalesce(p_comercios,'{}'),coalesce(p_categorias,'{}'))
    returning plone27_politicas_destino.id into pid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'politica_destino_crear','politica',pid::text,jsonb_build_object('ambito',p_ambito));
  return pid; end $$;

create or replace function plone27_bk_politica_desactivar(p_bank uuid,p_id uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare n int; begin
  with x as(update plone27_politicas_destino set activa=false where id=p_id and bank_id=p_bank returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Regla no encontrada en tu entidad'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'politica_destino_desactivar','politica',p_id::text,'{}'::jsonb);
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
