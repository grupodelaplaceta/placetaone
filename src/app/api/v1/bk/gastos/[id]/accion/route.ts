import { clientFrom } from "@/lib/apikey";

// Acción sobre un gasto (gastos:gestionar). accion: aprobar | rechazar | pagar. dip_actor = quien actúa.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "gastos:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const accion = String(b?.accion ?? "");
  if (accion === "aprobar") {
    const { data, error } = await a.db.rpc("plone27_gasto_aprobar", { p_bank: a.c.bank_id, p_gasto: id, p_actor: actor.data });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ resultado: data });
  }
  if (accion === "rechazar") {
    const { error } = await a.db.rpc("plone27_gasto_rechazar", { p_bank: a.c.bank_id, p_gasto: id, p_actor: actor.data, p_motivo: String(b?.motivo ?? "") });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ resultado: "rechazado" });
  }
  if (accion === "pagar") {
    const { data, error } = await a.db.rpc("plone27_gasto_pagar", { p_bank: a.c.bank_id, p_gasto: id, p_actor: actor.data });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ transaccion: data });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
