begin;
-- Placeta One · 0066 · Las empresas convocan subvenciones y bonos, abiertos a cualquiera de la entidad o dirigidos a otra empresa.
-- Cada convocatoria crea su programa con la cuenta de fondos de la empresa; se reutilizan reserva, caducidad y reversión.
-- Requiere 0065. Idempotente. NO ejecutado en PostgreSQL.

alter table plone27_convocatorias add column if not exists tipo text not null default 'subvencion' check(tipo in('subvencion','bono'));
alter table plone27_convocatorias add column if not exists dirigida_a text not null default 'todos' check(dirigida_a in('todos','empresa'));
alter table plone27_convocatorias add column if not exists empresa_destino uuid references plone27_empresas(id);
alter table plone27_convocatorias add column if not exists cuenta_fondos uuid references plone27_accounts(id);
alter table plone27_convocatorias add column if not exists programa uuid references plone27_grant_programs(id);
alter table plone27_convocatorias drop constraint if exists plone27_convocatorias_destino_check;
alter table plone27_convocatorias add constraint plone27_convocatorias_destino_check check((dirigida_a='empresa') = (empresa_destino is not null));

-- La empresa abre una convocatoria: crea su programa con la cuenta de fondos de la empresa
create or replace function plone27_convocatoria_empresa_crear(p_bank uuid,p_cip text,p_actor uuid,p_nombre text,p_tipo text,p_importe numeric,
    p_desde date,p_hasta date,p_caduca date,p_dirigida text,p_empresa_destino uuid,p_cuenta_fondos uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; emp uuid; pid uuid; cid uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_es_admin(p_actor) and not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para abrir convocatorias'; end if;
  if p_tipo not in('subvencion','bono') then raise exception 'Tipo no válido (subvención o bono)'; end if;
  if p_tipo='bono' and p_caduca is null then raise exception 'Un bono necesita fecha de caducidad'; end if;
  if p_caduca is not null and p_caduca<p_desde then raise exception 'La caducidad no puede ser anterior al inicio de la convocatoria'; end if;
  if p_dirigida not in('todos','empresa') then raise exception 'Destino no válido (todos o empresa)'; end if;
  if p_dirigida='empresa' and (p_empresa_destino is null or not exists(select 1 from plone27_empresas where id=p_empresa_destino and bank_id=p_bank)) then
    raise exception 'La empresa destinataria no existe en tu entidad';
  end if;
  select e.id into emp from plone27_empresas e where e.entidad_cip=p_cip and e.bank_id=p_bank;
  if emp is null then raise exception 'Empresa no encontrada'; end if;
  if p_cuenta_fondos is null or not exists(select 1 from plone27_empresa_cuentas where empresa_id=emp and account_id=p_cuenta_fondos) then
    raise exception 'La cuenta de fondos debe ser una cuenta de la empresa';
  end if;
  insert into plone27_grant_programs(name,kind,budget,funding_account) values(p_nombre,p_tipo,p_importe,p_cuenta_fondos)
    returning plone27_grant_programs.id into pid;
  insert into plone27_convocatorias(entidad,nombre,importe,desde,hasta,caduca,tipo,dirigida_a,empresa_destino,cuenta_fondos,programa)
    values(ent,p_nombre,p_importe,p_desde,p_hasta,p_caduca,p_tipo,p_dirigida,case when p_dirigida='empresa' then p_empresa_destino end,p_cuenta_fondos,pid)
    returning plone27_convocatorias.id into cid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'convocatoria_empresa_crear','convocatoria',cid::text,jsonb_build_object('tipo',p_tipo,'dirigida_a',p_dirigida,'importe',p_importe));
  return cid; end $$;

-- Conceder dentro de una convocatoria: respeta el destino y bloquea la autoconcesión
create or replace function plone27_convocatoria_conceder(p_bank uuid,p_cip text,p_conv uuid,p_beneficiary uuid,p_amount numeric,p_caduca date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; cv plone27_convocatorias; ben_bank uuid; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  select * into cv from plone27_convocatorias where id=p_conv and entidad=ent;
  if cv.id is null then raise exception 'Convocatoria no encontrada en tu entidad'; end if;
  if cv.estado<>'abierta' or current_date<cv.desde or current_date>cv.hasta then raise exception 'La convocatoria no está abierta hoy'; end if;
  if not plone27_es_admin(p_actor) and not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para conceder en esta convocatoria'; end if;
  if exists(select 1 from plone27_empresa_cuentas ec join plone27_empresa_cuentas ec2 on ec2.empresa_id=ec.empresa_id
            where ec.account_id=cv.cuenta_fondos and ec2.account_id=p_beneficiary) then
    raise exception 'No se puede conceder a una cuenta de la propia empresa';
  end if;
  if cv.dirigida_a='empresa' then
    if not exists(select 1 from plone27_empresa_cuentas where empresa_id=cv.empresa_destino and account_id=p_beneficiary) then
      raise exception 'La convocatoria está dirigida a otra empresa';
    end if;
  else
    select a.bank_id into ben_bank from plone27_accounts a where a.id=p_beneficiary;
    if ben_bank is distinct from p_bank then raise exception 'La convocatoria solo admite beneficiarios de tu entidad'; end if;
  end if;
  return plone27_grant_crear(cv.programa,p_beneficiary,p_amount,p_conv,p_caduca,p_actor); end $$;

-- Cerrar una convocatoria: ya no admite concesiones nuevas
create or replace function plone27_convocatoria_cerrar(p_bank uuid,p_cip text,p_conv uuid,p_actor uuid) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare ent uuid; n int; begin
  ent:=plone27_entidad_de(p_bank,p_cip);
  if ent is null then raise exception 'Entidad no encontrada'; end if;
  if not plone27_es_admin(p_actor) and not plone27_tiene_en_entidad(p_actor,ent,'presupuestar') then raise exception 'Sin permiso para cerrar convocatorias'; end if;
  with x as(update plone27_convocatorias set estado='cerrada' where id=p_conv and entidad=ent and estado='abierta' returning 1)
  select count(*) into n from x;
  if n=0 then raise exception 'Convocatoria no encontrada o ya cerrada'; end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'convocatoria_cerrar','convocatoria',p_conv::text,'{}'::jsonb); end $$;

-- Conceder: la permiso puede venir de la entidad de la convocatoria (no solo de una entidad con cuenta propia)
create or replace function plone27_grant_crear(p_program uuid,p_beneficiary uuid,p_amount numeric,p_convocatoria uuid,p_caduca date,p_actor uuid) returns uuid
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare pr plone27_grant_programs; cv plone27_convocatorias; ent_cv uuid; cad date; rid uuid; gid uuid; comprometido numeric; begin
  select * into pr from plone27_grant_programs where id=p_program;
  if pr.id is null then raise exception 'Programa no encontrado'; end if;
  if p_convocatoria is not null then
    select entidad into ent_cv from plone27_convocatorias where id=p_convocatoria;
    if not plone27_es_admin(p_actor) and not plone27_tiene_en_entidad(p_actor,ent_cv,'presupuestar') then raise exception 'Sin permiso para conceder en esta convocatoria'; end if;
  elsif not plone27_es_admin(p_actor) and not (exists(select 1 from plone27_entidades where account_id=pr.funding_account)
     and plone27_tiene_en_entidad(p_actor,pr.funding_account,'presupuestar')) then
    raise exception 'Sin permiso para conceder en este programa';
  end if;
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
  if comprometido+p_amount>pr.budget then raise exception 'Supera el presupuesto de la convocatoria o programa (disponible: %)', pr.budget-comprometido; end if;
  rid:=plone27_reserve(pr.funding_account,p_amount,'Autorización: '||pr.name,p_actor);
  insert into plone27_grants(program_id,beneficiary_account,granted,convocatoria,caduca,reserva,estado)
    values(p_program,p_beneficiary,p_amount,p_convocatoria,cad,rid,'activa') returning plone27_grants.id into gid;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail) values(p_actor,'subvencion_crear','grant',gid::text,jsonb_build_object('importe',p_amount,'caduca',cad));
  return gid; end $$;

-- Revertir: el subvencionante es la entidad de la convocatoria (o la entidad de la cuenta de fondos si no hay convocatoria)
create or replace function plone27_grant_revertir(p_grant uuid,p_just uuid,p_motivo text,p_actor uuid,p_bank uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare g plone27_grants; pr plone27_grant_programs; ent uuid; j record; n int:=0;
  total_dev numeric:=0; total_deuda numeric:=0; parte numeric; resto numeric; avail numeric; did uuid; begin
  select * into g from plone27_grants where id=p_grant for update;
  if g.id is null then raise exception 'Subvención no encontrada'; end if;
  select * into pr from plone27_grant_programs where id=g.program_id;
  if p_bank is not null and not exists(select 1 from plone27_accounts where id=pr.funding_account and bank_id=p_bank) then
    raise exception 'La subvención no pertenece a tu entidad';
  end if;
  if not plone27_es_admin(p_actor) then
    select cv.entidad into ent from plone27_convocatorias cv where cv.id=g.convocatoria;
    if ent is null then ent:=pr.funding_account; end if;
    if not exists(select 1 from plone27_entidades where account_id=ent) or not plone27_tiene_en_entidad(p_actor,ent,'ejecutar') then
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
    if g.reserva is not null and exists(select 1 from plone27_reservations where id=g.reserva and status='active') then
      update plone27_reservations set amount=amount+total_dev where id=g.reserva;
    else
      update plone27_grants set reserva=plone27_reserve(pr.funding_account,total_dev,'Reautorización: '||pr.name,p_actor) where id=p_grant;
    end if;
  end if;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,'subvencion_revertir','grant',p_grant::text,jsonb_build_object('abonos',n,'devuelto',total_dev,'deuda',total_deuda,'motivo',p_motivo));
  return jsonb_build_object('abonos',n,'devuelto',total_dev,'deuda',total_deuda,'estado',(select estado from plone27_grants where id=p_grant)); end $$;

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

do $$ begin raise notice 'Actualización 0066 aplicada correctamente.'; end $$;

commit;
