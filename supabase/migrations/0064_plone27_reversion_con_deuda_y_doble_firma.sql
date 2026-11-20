-- Placeta One · 0064 · Revertir un abono: lo disponible se devuelve y el resto queda como deuda (sin saldo negativo).
-- Se retira la excepción de la Junta a la doble firma en ajustes y publicación fiscal. Requiere 0063. Idempotente. NO ejecutado en PostgreSQL.

alter table plone27_debts add column if not exists creditor_account uuid references plone27_accounts(id);
alter table plone27_grant_reversiones add column if not exists devuelto numeric(18,2) not null default 0;
alter table plone27_grant_reversiones add column if not exists deuda numeric(18,2) not null default 0;
alter table plone27_grant_reversiones add column if not exists deuda_id uuid references plone27_debts(id);

-- Doble firma: sin excepciones (el proponente no aprueba su cambio)
create or replace function plone27_setting_approve(p_change uuid,p_approve boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_setting_changes; begin
  select * into c from plone27_setting_changes where id=p_change and status='pending';
  if c.id is null then raise exception 'Cambio no pendiente'; end if;
  if c.proposed_by is not distinct from p_actor then raise exception 'El proponente no puede aprobar su propio cambio'; end if;
  if p_approve then
    update plone27_setting_changes set approved_by=p_actor where id=p_change;
    perform plone27_setting_apply(p_change,p_actor);
  else
    update plone27_setting_changes set status='rejected',approved_by=p_actor where id=p_change;
  end if; end $$;

-- Publicación fiscal: aprobador distinto del autor, sin excepciones
create or replace function plone27_tax_publish(p_version uuid,p_approver uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v plone27_tax_rule_versions; begin
  select * into v from plone27_tax_rule_versions where id=p_version for update;
  if v.id is null or v.status<>'draft' then raise exception 'La versión no está en borrador'; end if;
  if p_approver is null or p_approver is not distinct from v.author then raise exception 'Publicar exige un aprobador distinto del autor'; end if;
  update plone27_tax_rule_versions set status='published',approver=p_approver,published_at=now(),fingerprint=plone27_version_fp(p_version) where id=p_version;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_publish','tax_version',p_version::text,jsonb_build_object('approver',p_approver)); end $$;

-- Revertir abonos: reversión completa si hay saldo; si no, lo disponible se devuelve y el resto es deuda
create or replace function plone27_grant_revertir(p_grant uuid,p_just uuid,p_motivo text,p_actor uuid,p_bank uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; pr plone27_grant_programs; j record; n int:=0;
  total_dev numeric:=0; total_deuda numeric:=0; parte numeric; resto numeric; avail numeric; did uuid; begin
  select * into g from plone27_grants where id=p_grant for update;
  if g.id is null then raise exception 'Subvención no encontrada'; end if;
  select * into pr from plone27_grant_programs where id=g.program_id;
  if p_bank is not null and not exists(select 1 from plone27_accounts where id=pr.funding_account and bank_id=p_bank) then
    raise exception 'La subvención no pertenece a tu entidad';
  end if;
  if not plone27_es_admin(p_actor) then
    if not exists(select 1 from plone27_entidades where account_id=pr.funding_account)
       or not plone27_tiene_en_entidad(p_actor,pr.funding_account,'ejecutar') then
      raise exception 'Solo el subvencionante o la Junta pueden revertir abonos';
    end if;
  end if;
  if coalesce(length(p_motivo),0)<10 then raise exception 'El motivo debe tener al menos 10 caracteres'; end if;
  if g.estado='revertida' then raise exception 'La subvención ya está revertida'; end if;
  for j in select * from plone27_justifications where grant_id=p_grant and status='paid' and reembolso_tx is not null
           and (p_just is null or id=p_just) loop
    avail:=greatest(plone27_available(g.beneficiary_account),0);
    did:=null;
    if avail>=j.amount then
      perform plone27_reverse('rev:'||j.id::text,j.reembolso_tx,p_motivo,p_actor);
      parte:=j.amount; resto:=0;
    else
      parte:=avail; resto:=j.amount-avail;
      if parte>0 then
        perform plone27_transfer('rev-dev:'||j.id::text,g.beneficiary_account,pr.funding_account,parte,'Devolución parcial de abono',p_actor);
      end if;
      insert into plone27_debts(account_id,principal,due_date,authorized_by,reason,creditor_account)
        values(g.beneficiary_account,resto,current_date,p_actor,'Reversión de abono: '||p_motivo,pr.funding_account)
        returning plone27_debts.id into did;
    end if;
    update plone27_justifications set status='rejected' where id=j.id;
    update plone27_grants set paid=paid-j.amount, approved=approved-j.amount where id=p_grant;
    insert into plone27_grant_reversiones(grant_id,justificacion,importe,motivo,actor,devuelto,deuda,deuda_id)
      values(p_grant,j.id,j.amount,p_motivo,p_actor,parte,resto,did);
    total_dev:=total_dev+parte; total_deuda:=total_deuda+resto; n:=n+1;
  end loop;
  if n=0 then raise exception 'No hay abonos que revertir'; end if;
  if p_just is null then
    if g.reserva is not null then perform plone27_release(g.reserva,p_actor); end if;
    update plone27_grants set estado='revertida' where id=p_grant;
  elsif total_dev>0 then
    -- Solo se vuelve a autorizar lo devuelto de inmediato; la deuda cobrada no vuelve a autorizarse
    if g.reserva is not null and exists(select 1 from plone27_reservations where id=g.reserva and status='active') then
      update plone27_reservations set amount=amount+total_dev where id=g.reserva;
    else
      update plone27_grants set reserva=plone27_reserve(pr.funding_account,total_dev,'Reautorización: '||pr.name,p_actor) where id=p_grant;
    end if;
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'subvencion_revertir','grant',p_grant::text,jsonb_build_object('abonos',n,'devuelto',total_dev,'deuda',total_deuda,'motivo',p_motivo));
  return jsonb_build_object('abonos',n,'devuelto',total_dev,'deuda',total_deuda,'estado',(select estado from plone27_grants where id=p_grant)); end $$;

-- Informe: incluye lo devuelto y la deuda de cada reversión
create or replace function plone27_grant_informe(p_grant uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; pr plone27_grant_programs; ben text; begin
  select * into g from plone27_grants where id=p_grant;
  if g.id is null then raise exception 'Subvención no encontrada'; end if;
  select * into pr from plone27_grant_programs where id=g.program_id;
  select a.iban into ben from plone27_accounts a where a.id=g.beneficiary_account;
  return jsonb_build_object(
    'subvencion',g.id,'programa',pr.name,'tipo',pr.kind,'beneficiario_iban',ben,
    'concedido',g.granted,'aprobado',g.approved,'pagado',g.paid,'pendiente_de_pago',g.granted-g.paid,
    'estado',g.estado,'caduca',g.caduca,
    'justificaciones',coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'factura',j.invoice_ref,'importe',j.amount,'estado',j.status,'transferencia',j.reembolso_tx) order by j.id)
                                from plone27_justifications j where j.grant_id=p_grant),'[]'::jsonb),
    'reversiones',coalesce((select jsonb_agg(jsonb_build_object('importe',r.importe,'devuelto',r.devuelto,'deuda',r.deuda,'motivo',r.motivo,'fecha',r.creada) order by r.creada)
                            from plone27_grant_reversiones r where r.grant_id=p_grant),'[]'::jsonb),
    'generado',now()); end $$;

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
