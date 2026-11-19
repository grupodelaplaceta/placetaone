import { clientFrom } from "@/lib/apikey";

// Acción sobre una tarea (tareas:gestionar). accion: validar | pagar | rechazar. dip_actor = quien actúa.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "tareas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const accion = String(b?.accion ?? "");
  if (accion === "validar") {
    const { data, error } = await a.db.rpc("plone27_tarea_validar", { p_bank: a.c.bank_id, p_tarea: id, p_actor: actor.data });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ resultado: data });
  }
  if (accion === "pagar") {
    const { data, error } = await a.db.rpc("plone27_tarea_pagar", { p_bank: a.c.bank_id, p_tarea: id, p_actor: actor.data });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ transaccion: data });
  }
  if (accion === "rechazar") {
    const { error } = await a.db.rpc("plone27_tarea_rechazar", { p_bank: a.c.bank_id, p_tarea: id, p_actor: actor.data, p_motivo: String(b?.motivo ?? "") });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ resultado: "rechazada" });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
