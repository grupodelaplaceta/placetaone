import { clientFrom } from "@/lib/apikey";

// GET: árbol de una entidad institucional (organigrama:leer).
export async function GET(req: Request) {
  const a = await clientFrom(req, "organigrama:leer");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const cip = new URL(req.url).searchParams.get("cip") ?? "";
  const { data, error } = await a.db.rpc("plone27_arbol", { p_bank: a.c.bank_id, p_cip: cip });
  if (error) return Response.json({ error: "No se puede cargar el organigrama" }, { status: 422 });
  if (!data) return Response.json({ error: "Entidad no encontrada" }, { status: 404 });
  return Response.json(data);
}

// POST: cambios del organigrama (organigrama:gestionar). dip_actor = quien actúa; dip = persona afectada.
// accion: unidad | puesto | nombrar | cesar | permiso | cerrar_unidad
export async function POST(req: Request) {
  const a = await clientFrom(req, "organigrama:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const cip = String(b?.cip ?? "");
  const actorRes = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return Response.json({ error: actorRes.error.message }, { status: 422 });
  const accion = String(b?.accion ?? "");
  let res;
  if (accion === "unidad") {
    res = await a.db.rpc("plone27_org_unidad_nueva", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data, p_tipo: String(b?.tipo ?? ""), p_padre: b?.padre ? String(b.padre) : null, p_nombre: String(b?.nombre ?? ""), p_codigo: b?.codigo ? String(b.codigo) : null });
    return res.error ? Response.json({ error: res.error.message }, { status: 422 }) : Response.json({ unidad: res.data }, { status: 201 });
  }
  if (accion === "puesto") {
    res = await a.db.rpc("plone27_org_puesto_nuevo", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data, p_unidad: String(b?.unidad ?? ""), p_nombre: String(b?.nombre ?? ""), p_titulares: Number(b?.titulares ?? 1) });
    return res.error ? Response.json({ error: res.error.message }, { status: 422 }) : Response.json({ puesto: res.data }, { status: 201 });
  }
  if (accion === "nombrar") {
    const persona = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip ?? "") });
    if (persona.error) return Response.json({ error: persona.error.message }, { status: 422 });
    res = await a.db.rpc("plone27_org_nombrar", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data, p_puesto: String(b?.puesto ?? ""), p_persona: persona.data, p_motivo: String(b?.motivo ?? "") });
    return res.error ? Response.json({ error: res.error.message }, { status: 422 }) : Response.json({ nombramiento: res.data }, { status: 201 });
  }
  if (accion === "cesar") {
    res = await a.db.rpc("plone27_org_cesar", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data, p_nombramiento: String(b?.nombramiento ?? ""), p_motivo: String(b?.motivo ?? "") });
    return res.error ? Response.json({ error: res.error.message }, { status: 422 }) : Response.json({ cesado: true });
  }
  if (accion === "permiso") {
    res = await a.db.rpc("plone27_org_permiso", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data, p_puesto: String(b?.puesto ?? ""), p_accion: String(b?.permiso ?? ""), p_limite: b?.limite ? Number(b.limite) : null });
    return res.error ? Response.json({ error: res.error.message }, { status: 422 }) : Response.json({ configurado: true });
  }
  if (accion === "cerrar_unidad") {
    res = await a.db.rpc("plone27_org_cerrar_unidad", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data, p_unidad: String(b?.unidad ?? ""), p_motivo: String(b?.motivo ?? "") });
    return res.error ? Response.json({ error: res.error.message }, { status: 422 }) : Response.json({ cerrada: true });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
