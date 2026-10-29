-- 0014 · Arreglos y rendimiento. Idempotente: se puede ejecutar varias veces y sobre cualquier estado (0013 aplicada).
-- Ejecutar completo en Supabase → SQL Editor.

-- ========== 1. ERROR: plone27_certification_report() fallaba con «column reference "c.amount" is ambiguous»
-- (rompía /admin/infraestructura y /admin/destinos). El alias del subselect chocaba con la variable plpgsql «c».
create or replace function plone27_certification_report() returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c record; prev text:='GENESIS'; h text; total int:=0; rota int:=0; disc int:=0; alterados int; reg int:=0; fpd int; sin int; begin
  for c in select * from plone27_tax_certificates order by seq loop
    total:=total+1;
    if c.prev_hash<>prev then rota:=rota+1; end if;
    h:=encode(sha256(convert_to(plone27_cert_text(c.prev_hash,c.kind,c.subject_id,c.version_id,c.fingerprint,c.base::text,c.amount::text,c.inputs),'utf8')),'hex');
    if h<>c.hash then rota:=rota+1; end if;
    prev:=c.hash;
    if c.kind='recibo' then
      if plone27_tax_calc(c.version_id,c.base)<>c.amount then disc:=disc+1; end if;
    elsif c.kind='recargo' then
      if round(c.base*(c.inputs->>'tramo')::numeric/100,2)-(c.inputs->>'cobrado_previo')::numeric<>c.amount then disc:=disc+1; end if;
    else reg:=reg+1; end if;
  end loop;
  select count(*) into fpd from plone27_tax_rule_versions v where v.status='published' and v.fingerprint is distinct from plone27_version_fp(v.id);
  select count(*) into alterados from plone27_tax_receipts r
    join lateral (select k.amount,k.base from plone27_tax_certificates k where k.subject_id=r.id order by k.seq desc limit 1) u on true
    where r.amount<>u.amount or r.base<>u.base;
  select count(*) into sin from plone27_tax_receipts r where not exists(select 1 from plone27_tax_certificates k where k.subject_id=r.id);
  return jsonb_build_object('certificados',total,'cadena_rota',rota,'importes_no_recalculan',disc,'importes_sin_certificado_vigente',alterados,
    'huella_norma_discrepante',fpd,'recibos_sin_certificado',sin,'certificados_informativos',reg,
    'estado',case when rota+disc+alterados+fpd+sin=0 then 'OK' else 'REVISAR' end);
end $$;

-- ========== 2. La pasarela /api/rpc añadía p_actor a funciones que no lo tienen → «function not found».
-- Sobrecargas con p_actor (ignorado): funcionan con cualquier versión del front.
create or replace function plone27_certification_report(p_actor uuid) returns jsonb language sql stable security definer set search_path=public as
  $$ select plone27_certification_report() $$;
create or replace function plone27_iva_report(p_desde date, p_hasta date, p_actor uuid) returns jsonb language sql stable security definer set search_path=public as
  $$ select plone27_iva_report(p_desde,p_hasta) $$;

-- ========== 3. RENDIMIENTO: índice en cada clave foránea que no lo tenga (joins, borrados y filtros del panel)
do $$ declare r record; begin
  for r in
    select c.conrelid::regclass::text as tbl, c.conrelid as relid, c.conkey as ck, string_agg(quote_ident(a.attname),',' order by k.ord) as cols,
           string_agg(a.attname,'_' order by k.ord) as nm
      from pg_constraint c
      cross join lateral unnest(c.conkey) with ordinality as k(attnum,ord)
      join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum
     where c.contype='f' and c.connamespace='public'::regnamespace and c.conrelid::regclass::text like 'plone27\_%'
       and not exists(select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid and (i.indkey::int2[])[0:array_length(c.conkey,1)-1]=c.conkey)
     group by c.conrelid,c.oid,c.conkey
  loop
    execute format('create index if not exists %I on %s (%s)', left('ix_'||replace(r.tbl,'plone27_','')||'_'||r.nm,63), r.tbl, r.cols);
  end loop;
end $$;

-- Índices para las ordenaciones y filtros que usa el panel (solo si la columna existe)
do $$ declare x text[]; begin
  foreach x slice 1 in array array[
    ['plone27_transactions','created_at desc'], ['plone27_tax_receipts','created_at desc'], ['plone27_tax_receipts','status'], ['plone27_tax_receipts','due_date'],
    ['plone27_incidents','at desc'], ['plone27_incidents','status'], ['plone27_approvals','at desc'], ['plone27_disputes','opened_at desc'], ['plone27_disputes','status'],
    ['plone27_iva_findings','detected_at desc'], ['plone27_iva_findings','status'], ['plone27_outbox','status'], ['plone27_outbox','created_at'],
    ['plone27_policies','created_at desc'], ['plone27_ledger_entries','created_at desc'], ['plone27_scheduled','status'], ['plone27_subscriptions','period_end'],
    ['plone27_plan_items','status'], ['plone27_rbu_bonuses','status'], ['plone27_contracts','status'], ['plone27_plans','status'],
    ['plone27_setting_changes','status'], ['plone27_audit_log','at desc'], ['plone27_audit_log','entity'], ['plone27_tax_certificates','subject_id'],
    ['plone27_accounts','status'], ['plone27_banks','status'], ['plone27_cards','status'], ['plone27_batches','status'], ['plone27_grants','program_id']]
  loop
    if to_regclass('public.'||x[1]) is not null
       and exists(select 1 from pg_attribute where attrelid=to_regclass('public.'||x[1]) and attname=split_part(x[2],' ',1) and not attisdropped) then
      execute format('create index if not exists %I on %I (%s)', 'ix_'||replace(x[1],'plone27_','')||'_'||replace(replace(x[2],' desc',''),' ','_')||case when x[2] like '% desc' then '_d' else '' end, x[1], x[2]);
    end if;
  end loop;
end $$;

-- ========== 4. SEGURIDAD: RLS en todo y permisos solo para service_role (incluye las funciones nuevas de esta migración)
do $$ declare t text; f text; begin
  for t in select tablename from pg_tables where schemaname='public' and tablename like 'plone27\_%' loop
    execute format('alter table %I enable row level security',t);
    if t not in('plone27_api_clients','plone27_webhooks') and not exists(select 1 from pg_policies p where p.tablename=t and p.policyname='staff_read') then
      execute format('create policy staff_read on %I for select using (plone27_has_role(array[''auditor'',''financiero'',''fiscal'',''financiacion'',''gestor_bancario'',''aprobador'']))',t); end if;
  end loop;
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'plone27\_%' and p.proname not in('plone27_has_role','plone27_bank_visible') loop
    execute format('revoke all on function %s from public,anon,authenticated',f); execute format('grant execute on function %s to service_role',f); end loop;
  execute 'grant select on plone27_account_balances, plone27_alerts to service_role';
end $$;

-- ========== 5. LISTO PARA USAR: da de alta como administrador a tu usuario de Auth (si ya existe en Authentication → Users).
-- Cambia el correo si usas otro. Si el usuario aún no existe, no hace nada.
insert into plone27_staff(user_id,role,active)
  select u.id,'admin',true from auth.users u where lower(u.email)=lower('junta@laplaceta.org')
  on conflict (user_id) do update set role='admin', active=true;

-- ========== 6. Estadísticas al día para que el planificador use los índices nuevos
analyze;
