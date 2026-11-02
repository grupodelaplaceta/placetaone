-- Solicitudes: producto de la solicitud, apertura inmediata de cuentas de producto y revisión del personal.

alter table plone27_solicitudes add column if not exists product_id uuid references plone27_products(id);
alter table plone27_solicitudes add column if not exists nota text;

-- Solicitud de un producto de cuenta. Si el producto es de cuenta (sin crédito) se abre al momento.
-- Los préstamos y productos de crédito quedan pendientes para que el personal los revise.
create or replace function plone27_user_request_product(p_user uuid,p_bank uuid,p_product uuid,p_motivo text,p_clave text) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare p plone27_products; sid uuid; est text; cuenta jsonb; begin
  select * into p from plone27_products where id=p_product and bank_id=p_bank and status='active'
    and (valid_from is null or valid_from<=current_date) and (valid_to is null or valid_to>=current_date);
  if p.id is null then raise exception 'Producto no disponible en tu entidad'; end if;
  if coalesce(length(p_motivo),0)>500 then raise exception 'Motivo demasiado largo (máximo 500)'; end if;

  insert into plone27_solicitudes(persona,bank_id,tipo,importe,motivo,clave_idem,product_id)
    values(p_user,p_bank,'cuenta',0,p_motivo,p_clave,p_product)
    on conflict(clave_idem) do update set clave_idem=excluded.clave_idem
    returning id, estado into sid, est;

  -- Reintento de la misma solicitud: no se vuelve a abrir nada.
  if est<>'pendiente' then return jsonb_build_object('solicitud',sid,'estado',est); end if;

  if p.kind like 'account\_%' and p.kind<>'internal_credit' then
    cuenta := plone27_open_account_p(p_product, coalesce(p.name,'Cuenta'), p_user, p_user);
    update plone27_solicitudes set estado='aprobada', resuelta=now(), nota='Abierta automáticamente' where id=sid;
    insert into plone27_audit_log(actor,action,entity,entity_id,detail)
      values(p_user,'solicitud_auto_aprobada','solicitud',sid::text,jsonb_build_object('producto',p_product));
    return jsonb_build_object('solicitud',sid,'estado','aprobada','cuenta',cuenta);
  end if;
  return jsonb_build_object('solicitud',sid,'estado','pendiente');
end $$;

-- Decisión del personal sobre una solicitud pendiente. No puede decidir quien la pidió.
create or replace function plone27_solicitud_decidir(p_id uuid,p_actor uuid,p_aprobar boolean,p_nota text) returns void
language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare s plone27_solicitudes; begin
  select * into s from plone27_solicitudes where id=p_id for update;
  if s.id is null then raise exception 'Solicitud no encontrada'; end if;
  if s.estado<>'pendiente' then raise exception 'La solicitud ya está resuelta'; end if;
  if p_actor=s.persona then raise exception 'Nadie puede resolver su propia solicitud'; end if;
  update plone27_solicitudes set estado=case when p_aprobar then 'aprobada' else 'rechazada' end,
    resuelta=now(), resuelta_por=p_actor, nota=left(coalesce(p_nota,''),300) where id=p_id;
  insert into plone27_audit_log(actor,action,entity,entity_id,detail)
    values(p_actor,case when p_aprobar then 'solicitud_aprobada' else 'solicitud_rechazada' end,'solicitud',p_id::text,jsonb_build_object('tipo',s.tipo));
end $$;
