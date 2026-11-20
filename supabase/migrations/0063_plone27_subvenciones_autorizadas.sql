-- Placeta One · 0063 · Subvenciones con fondos autorizados, caducidad por convocatoria, reversión de abonos,
-- informe de justificación y admin con prioridad en las reglas de doble firma. Requiere 0062. Idempotente. NO ejecutado en PostgreSQL.

alter table plone27_convocatorias add column if not exists caduca date;
alter table plone27_grants add column if not exists convocatoria uuid references plone27_convocatorias(id);
alter table plone27_grants add column if not exists caduca date;
alter table plone27_grants add column if not exists reserva uuid references plone27_reservations(id);
alter table plone27_grants add column if not exists estado text not null default 'activa';
alter table plone27_grants drop constraint if exists plone27_grants_estado_check;
alter table plone27_grants add constraint plone27_grants_estado_check check(estado in('activa','caducada','revertida'));
alter table plone27_justifications add column if not exists reembolso_tx uuid references plone27_transactions(id);

create table if not exists plone27_grant_reversiones(
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null references plone27_grants(id),
  justificacion uuid references plone27_justifications(id),
  importe numeric(18,2) not null check(importe>0),
  motivo text not null check(length(motivo) between 10 and 500),
  actor uuid,
  creada timestamptz not null default now());

-- La Junta (rol admin) tiene prioridad en las reglas de doble firma
create or replace function plone27_es_admin(p uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from plone27_staff where user_id=p and active and role='admin') $$;

create or replace function plone27_setting_approve(p_change uuid,p_approve boolean,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare c plone27_setting_changes; begin
  select * into c from plone27_setting_changes where id=p_change and status='pending';
  if c.id is null then raise exception 'Cambio no pendiente'; end if;
  if c.proposed_by is not distinct from p_actor and not plone27_es_admin(p_actor) then raise exception 'El proponente no puede aprobar su propio cambio'; end if;
  if p_approve then
    update plone27_setting_changes set approved_by=p_actor where id=p_change;
    perform plone27_setting_apply(p_change,p_actor);
  else
    update plone27_setting_changes set status='rejected',approved_by=p_actor where id=p_change;
  end if; end $$;

create or replace function plone27_tax_publish(p_version uuid,p_approver uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare v plone27_tax_rule_versions; begin
  select * into v from plone27_tax_rule_versions where id=p_version for update;
  if v.id is null or v.status<>'draft' then raise exception 'La versión no está en borrador'; end if;
  if p_approver is null or (p_approver is not distinct from v.author and not plone27_es_admin(p_approver)) then raise exception 'Publicar exige un aprobador distinto del autor'; end if;
  update plone27_tax_rule_versions set status='published',approver=p_approver,published_at=now(),fingerprint=plone27_version_fp(p_version) where id=p_version;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'tax_publish','tax_version',p_version::text,jsonb_build_object('approver',p_approver)); end $$;

-- Caducidad propia de cada convocatoria
create or replace function plone27_convocatoria_caducidad_fijar(p_conv uuid,p_caduca date,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare cv plone27_convocatorias; begin
  select * into cv from plone27_convocatorias where id=p_conv;
  if cv.id is null then raise exception 'Convocatoria no encontrada'; end if;
  if not plone27_es_admin(p_actor) and not plone27_tiene_en_entidad(p_actor,cv.entidad,'presupuestar') then raise exception 'Sin permiso para fijar la caducidad'; end if;
  if p_caduca is not null and p_caduca<cv.desde then raise exception 'La caducidad no puede ser anterior al inicio de la convocatoria'; end if;
  update plone27_convocatorias set caduca=p_caduca where id=p_conv;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'convocatoria_caducidad','convocatoria',p_conv::text,jsonb_build_object('caduca',p_caduca)); end $$;

-- Crear una subvención o bono: reserva el importe en la cuenta del programa (fondos autorizados)
create or replace function plone27_grant_crear(p_program uuid,p_beneficiary uuid,p_amount numeric,p_convocatoria uuid,p_caduca date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pr plone27_grant_programs; cv plone27_convocatorias; cad date; rid uuid; gid uuid; comprometido numeric; begin
  select * into pr from plone27_grant_programs where id=p_program;
  if pr.id is null then raise exception 'Programa no encontrado'; end if;
  if not plone27_es_admin(p_actor) and not (exists(select 1 from plone27_entidades where account_id=pr.funding_account)
     and plone27_tiene_en_entidad(p_actor,pr.funding_account,'presupuestar')) then raise exception 'Sin permiso para conceder en este programa'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Importe no válido'; end if;
  if not exists(select 1 from plone27_accounts where id=p_beneficiary) then raise exception 'Beneficiario no encontrado'; end if;
  if p_convocatoria is not null then
    select * into cv from plone27_convocatorias where id=p_convocatoria;
    if cv.id is null then raise exception 'Convocatoria no encontrada'; end if;
  end if;
  cad:=coalesce(p_caduca,cv.caduca);
  if pr.kind='bono' and cad is null then raise exception 'Un bono necesita fecha de caducidad (por convocatoria o explícita)'; end if;
  if cad is not null and cad<=current_date then raise exception 'La caducidad debe ser posterior a hoy'; end if;
  select coalesce(sum(granted),0) into comprometido from plone27_grants where program_id=p_program and estado='activa';
  if comprometido+p_amount>pr.budget then raise exception 'Supera el presupuesto del programa (disponible: %)', pr.budget-comprometido; end if;
  rid:=plone27_reserve(pr.funding_account,p_amount,'Autorización: '||pr.name,p_actor);
  insert into plone27_grants(program_id,beneficiary_account,granted,convocatoria,caduca,reserva,estado)
    values(p_program,p_beneficiary,p_amount,p_convocatoria,cad,rid,'activa') returning plone27_grants.id into gid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'subvencion_crear','grant',gid::text,jsonb_build_object('importe',p_amount,'caduca',cad));
  return gid; end $$;

-- Justificar: solo subvenciones activas
create or replace function plone27_justify(p_grant uuid,p_tx uuid,p_invoice text,p_amount numeric,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; spent numeric; jid uuid; begin
  select * into g from plone27_grants where id=p_grant for update;
  if g.id is null then raise exception 'Subvención no encontrada'; end if;
  if g.estado<>'activa' then raise exception 'La subvención no está activa (%)', g.estado; end if;
  select sum(e.amount) into spent from plone27_ledger_entries e join plone27_transactions t on t.id=e.transaction_id
    where e.transaction_id=p_tx and e.account_id=g.beneficiary_account and e.direction='debit' and t.status='posted';
  if coalesce(spent,0)<p_amount then raise exception 'Transacción no elegible o importe excesivo'; end if;
  if coalesce((select sum(amount) from plone27_justifications where grant_id=p_grant and status<>'rejected'),0)+p_amount>g.granted then raise exception 'Supera lo concedido'; end if;
  insert into plone27_justifications(grant_id,transaction_id,invoice_ref,amount) values(p_grant,p_tx,p_invoice,p_amount)
    returning plone27_justifications.id into jid;
  return jid; end $$;

-- Abonar: consume la autorización (reserva) del importe justificado
create or replace function plone27_reimburse(p_key text,p_just uuid,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare j plone27_justifications; g plone27_grants; f uuid; tx uuid; r plone27_reservations; begin
  select * into j from plone27_justifications where id=p_just for update;
  if j.id is null or j.status not in('pending','approved') then raise exception 'Ya pagada o rechazada'; end if;
  select * into g from plone27_grants where id=j.grant_id for update;
  if g.estado<>'activa' then raise exception 'La subvención no está activa (%)', g.estado; end if;
  select funding_account into f from plone27_grant_programs where id=g.program_id;
  if j.status='pending' then
    update plone27_grants set approved=approved+j.amount where id=g.id;
    update plone27_justifications set status='approved' where id=p_just;
  end if;
  if g.reserva is not null then
    select * into r from plone27_reservations where id=g.reserva for update;
    if r.status<>'active' or r.amount<j.amount then raise exception 'La autorización de fondos no cubre este importe'; end if;
    if r.amount=j.amount then update plone27_reservations set status='released' where id=r.id;
    else update plone27_reservations set amount=amount-j.amount where id=r.id; end if;
  elsif plone27_available(f)<j.amount then
    return null;
  end if;
  tx:=plone27_transfer(p_key,f,g.beneficiary_account,j.amount,'Reembolso',p_actor);
  update plone27_grants set paid=paid+j.amount where id=g.id;
  update plone27_justifications set status='paid', reembolso_tx=tx where id=p_just;
  return tx; end $$;

-- Caducidad diaria: las subvenciones vencidas liberan su autorización sin pagar
create or replace function plone27_grants_caducar(p_actor uuid) returns int
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; n int:=0; begin
  for g in select * from plone27_grants where estado='activa' and caduca is not null and caduca<current_date for update loop
    update plone27_grants set estado='caducada' where id=g.id;
    if g.reserva is not null then perform plone27_release(g.reserva,p_actor); end if;
    n:=n+1;
  end loop;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'subvencion_caducidad','grant',null,jsonb_build_object('caducadas',n));
  return n; end $$;

-- Revertir un abono (o toda la subvención): revierte el reembolso y devuelve la autorización
create or replace function plone27_grant_revertir(p_grant uuid,p_just uuid,p_motivo text,p_actor uuid,p_bank uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; pr plone27_grant_programs; j record; total numeric:=0; n int:=0; begin
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
    perform plone27_reverse('rev:'||j.id::text,j.reembolso_tx,p_motivo,p_actor);
    update plone27_justifications set status='rejected' where id=j.id;
    update plone27_grants set paid=paid-j.amount, approved=approved-j.amount where id=p_grant;
    insert into plone27_grant_reversiones(grant_id,justificacion,importe,motivo,actor) values(p_grant,j.id,j.amount,p_motivo,p_actor);
    total:=total+j.amount; n:=n+1;
  end loop;
  if n=0 then raise exception 'No hay abonos que revertir'; end if;
  if p_just is null then
    if g.reserva is not null then perform plone27_release(g.reserva,p_actor); end if;
    update plone27_grants set estado='revertida' where id=p_grant;
  elsif g.reserva is not null and exists(select 1 from plone27_reservations where id=g.reserva and status='active') then
    update plone27_reservations set amount=amount+total where id=g.reserva;
  else
    update plone27_grants set reserva=plone27_reserve(pr.funding_account,total,'Reautorización: '||pr.name,p_actor) where id=p_grant;
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'subvencion_revertir','grant',p_grant::text,jsonb_build_object('importe',total,'abonos',n,'motivo',p_motivo));
  return jsonb_build_object('revertido',total,'abonos',n,'estado',(select estado from plone27_grants where id=p_grant)); end $$;

-- Informe de justificación de una subvención
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
    'reversiones',coalesce((select jsonb_agg(jsonb_build_object('importe',r.importe,'motivo',r.motivo,'fecha',r.creada) order by r.creada)
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
