begin;
-- Placeta One · 0075 · Las multas respetan el saldo inembargable en el cobro automático.
-- Las deudas que nacen de una multa se marcan como inembargables: el cobro solo toma lo que supere el mínimo.
-- Requiere 0074. Idempotente. NO ejecutado en PostgreSQL.

alter table plone27_debts add column if not exists inembargable boolean not null default false;

-- Cobro automático: las deudas inembargables cobran solo lo que supere el saldo protegido
create or replace function plone27_autocollect_debts(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare r record; n int:=0; floor_pz numeric; libre numeric; monto numeric; begin
  if not (plone27_setting('autocobro_habilitado'))::boolean then return 0; end if;
  floor_pz:=(plone27_setting('sancion_inembargable_pz')#>>'{}')::numeric;
  for r in select d.id,d.account_id,d.creditor_account,d.inembargable,
             d.principal+d.authorized_charges-d.paid pend
           from plone27_debts d
           where not d.disputed and d.paid<d.principal+d.authorized_charges and d.due_date<=current_date and d.creditor_account is not null
           order by d.due_date,d.id loop
    if r.inembargable then
      libre:=greatest(plone27_available(r.account_id)-floor_pz,0);
      monto:=least(r.pend,libre);
      continue when monto<=0;
    else
      continue when not plone27_collectable(r.account_id,r.pend);
      monto:=r.pend;
    end if;
    begin
      perform plone27_debt_pay('auto:debt:'||r.id||':'||monto,r.id,monto,p_actor);
      n:=n+1;
    exception when others then
      insert into plone27_incidents(kind,detail) values('autocobro_fallido',jsonb_build_object('deuda',r.id,'err',sqlerrm));
    end;
  end loop;
  return n; end $$;

-- Ejecutar sanción: la deuda de una multa nace inembargable
create or replace function plone27_sancion_ejecutar(p_id uuid,p_actor uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_sanciones; k text; inemb numeric; disp numeric; maxi numeric; tx uuid; rid uuid; did uuid; cobro timestamptz; begin
  if p_actor is not null and not plone27_es_admin(p_actor) then raise exception 'Solo la Junta ejecuta sanciones'; end if;
  select * into s from plone27_sanciones where id=p_id for update;
  if s.id is null or s.estado<>'firme' then raise exception 'La sanción no está firme'; end if;
  if s.ejecucion_prevista is null or s.ejecucion_prevista>now() then raise exception 'La ejecución no está programada o aún no ha llegado su hora'; end if;
  select a.kind into k from plone27_accounts a where a.id=s.cuenta;
  perform set_config('plone27.sancion','on',true);
  if k='joven' then perform set_config('plone27.joven_op','on',true); end if;
  inemb:=(plone27_setting('sancion_inembargable_pz')#>>'{}')::numeric;
  disp:=plone27_available(s.cuenta);
  maxi:=greatest(disp-inemb,0);
  if s.tipo='multa' and k<>'joven' then
    insert into plone27_debts(account_id,principal,due_date,authorized_by,reason,creditor_account,inembargable)
      values(s.cuenta,s.importe,current_date+15,p_actor,'Multa: '||s.motivo,s.destino,true) returning plone27_debts.id into did;
    cobro:=((current_date+15)::timestamp+interval '4 hours') at time zone 'UTC';
    insert into plone27_avisos(bank_id,cuenta,tipo,sancion,mensaje,ejecuta_en,visible_desde)
      values(s.bank_id,s.cuenta,'cobro_multa_previsto',p_id,
        'Se cobrará la multa a partir del '||to_char(cobro,'DD/MM/YYYY')||' con tu saldo disponible. Se respetarán '||inemb||' Pz inembargables.',
        cobro,cobro-interval '5 hours');
    update plone27_sanciones set estado='ejecutada', deuda=did, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
    return jsonb_build_object('tipo','multa','deuda',did);
  end if;
  if s.tipo in('multa','incautacion') then
    if s.importe>maxi then raise exception 'Solo es cobrable hasta % Pz: el resto es inembargable', maxi; end if;
    tx:=plone27_transfer('sancion:'||s.id::text,s.cuenta,s.destino,s.importe,
      case when s.tipo='multa' then 'Multa: ' else 'Incautación: ' end||left(s.motivo,80),p_actor);
    update plone27_sanciones set estado='ejecutada', transaccion=tx, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
    return jsonb_build_object('tipo',s.tipo,'transaccion',tx);
  end if;
  if s.importe>maxi then raise exception 'Solo es embargable hasta % Pz: el resto es inembargable', maxi; end if;
  rid:=plone27_reserve(s.cuenta,s.importe,'Embargo: '||left(s.motivo,80),p_actor);
  update plone27_sanciones set estado='ejecutada', reserva=rid, ejecutada_por=p_actor, ejecutada_at=now() where id=p_id;
  return jsonb_build_object('tipo','embargo','reserva',rid); end $$;

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

do $$ begin raise notice 'Actualización 0075 aplicada correctamente.'; end $$;

commit;
