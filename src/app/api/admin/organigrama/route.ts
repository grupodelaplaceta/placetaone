import { staffFrom } from "@/lib/supabase";

// Organigrama de la cuenta institucional. Lectura: personal de auditoría, gestión y aprobación. Cambios: aprobador.
const TIPOS = ["junta", "administracion", "departamento", "subdepartamento", "proyecto", "institucion", "unidad_control"];
const PERMISOS = ["consultar", "proponer", "aprobar", "ejecutar"];

export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [entidades, unidades, puestos, nombramientos, delegaciones] = await Promise.all([
    s.db.from("plone27_entidades").select("account_id,cip,nombre,activa,creada").order("creada", { ascending: false }),
    s.db.from("plone27_unidades").select("id,entidad,padre,tipo,nombre,codigo,activa").order("nombre"),
    s.db.from("plone27_puestos").select("id,unidad,nombre,titulares_max,activo").order("nombre"),
    s.db.from("plone27_nombramientos").select("id,puesto,persona,desde,hasta,motivo").order("desde", { ascending: false }).limit(500),
    s.db.from("plone27_delegaciones").select("id,unidad,persona,permiso,limite,desde,hasta,motivo,revocada_at").order("desde", { ascending: false }).limit(500),
  ]);
  const error = entidades.error || unidades.error || puestos.error || nombramientos.error || delegaciones.error;
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json({ entidades: entidades.data ?? [], unidades: unidades.data ?? [], puestos: puestos.data ?? [],
    nombramientos: nombramientos.data ?? [], delegaciones: delegaciones.data ?? [] });
}

// Acciones: entidad, unidad, puesto, nombrar, cesar, delegar, revocar_delegacion
export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const accion = String(b?.accion ?? "");
  const txt = (v: unknown) => String(v ?? "").trim();
  const fail = (m: string) => Response.json({ error: m }, { status: 422 });

  if (accion === "entidad") {
    const cuenta = await s.db.from("plone27_accounts").select("id,bank_id").eq("iban", txt(b?.iban)).maybeSingle();
    if (!cuenta.data) return fail("No existe una cuenta con ese IBAN");
    const { data, error } = await s.db.rpc("plone27_entidad_alta", { p_bank: cuenta.data.bank_id, p_account: cuenta.data.id, p_nombre: txt(b?.nombre), p_actor: s.id });
    return error ? fail(error.message) : Response.json({ cip: data }, { status: 201 });
  }
  if (accion === "unidad") {
    if (!TIPOS.includes(txt(b?.tipo))) return fail("Tipo de unidad no válido");
    const { data, error } = await s.db.rpc("plone27_unidad_alta", { p_entidad: txt(b?.entidad), p_tipo: txt(b?.tipo),
      p_padre: txt(b?.padre) || null, p_nombre: txt(b?.nombre), p_codigo: txt(b?.codigo) || null, p_actor: s.id });
    return error ? fail(error.message) : Response.json({ unidad: data }, { status: 201 });
  }
  if (accion === "puesto") {
    const { data, error } = await s.db.rpc("plone27_puesto_alta", { p_unidad: txt(b?.unidad), p_nombre: txt(b?.nombre),
      p_titulares: Number(b?.titulares ?? 1), p_actor: s.id });
    return error ? fail(error.message) : Response.json({ puesto: data }, { status: 201 });
  }
  if (accion === "nombrar") {
    const persona = await s.db.rpc("plone27_persona", { p_dip: txt(b?.dip) });
    if (persona.error) return fail(persona.error.message);
    const { data, error } = await s.db.rpc("plone27_nombrar", { p_puesto: txt(b?.puesto), p_persona: persona.data, p_motivo: txt(b?.motivo), p_actor: s.id });
    return error ? fail(error.message) : Response.json({ nombramiento: data }, { status: 201 });
  }
  if (accion === "cesar") {
    const { error } = await s.db.rpc("plone27_cesar", { p_nombramiento: txt(b?.nombramiento), p_motivo: txt(b?.motivo), p_actor: s.id });
    return error ? fail(error.message) : Response.json({ cesado: true });
  }
  if (accion === "delegar") {
    if (!PERMISOS.includes(txt(b?.permiso))) return fail("Permiso de delegación no válido");
    const persona = await s.db.rpc("plone27_persona", { p_dip: txt(b?.dip) });
    if (persona.error) return fail(persona.error.message);
    const { data, error } = await s.db.rpc("plone27_delegar", { p_unidad: txt(b?.unidad), p_persona: persona.data, p_permiso: txt(b?.permiso),
      p_limite: b?.limite ? Number(b.limite) : null, p_hasta: txt(b?.hasta) || null, p_motivo: txt(b?.motivo), p_actor: s.id });
    return error ? fail(error.message) : Response.json({ delegacion: data }, { status: 201 });
  }
  if (accion === "revocar_delegacion") {
    const { error } = await s.db.rpc("plone27_revocar_delegacion", { p_id: txt(b?.id), p_actor: s.id });
    return error ? fail(error.message) : Response.json({ revocada: true });
  }
  if (accion === "permiso") {
    const acc = txt(b?.permiso);
    if (!["proponer", "aprobar", "ejecutar", "presupuestar", "reasignar", "retribuir", "organigrama", "cerrar"].includes(acc)) return fail("Permiso no válido");
    const { error } = await s.db.rpc("plone27_puesto_permiso_fijar_staff", { p_puesto: txt(b?.puesto), p_accion: acc, p_limite: b?.limite ? Number(b.limite) : null, p_actor: s.id });
    return error ? fail(error.message) : Response.json({ ok: true });
  }
  return fail("Acción no válida");
}
