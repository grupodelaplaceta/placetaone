import { clientFrom } from "@/lib/apikey";

// Mueve presupuesto entre dos unidades con la misma unidad superior (presupuestos:gestionar).
export async function POST(req: Request) {
  const a = await clientFrom(req, "presupuestos:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { error } = await a.db.rpc("plone27_presupuesto_reasignar", { p_bank: a.c.bank_id, p_cip: String(b?.cip ?? ""), p_actor: actor.data,
    p_desde: String(b?.desde ?? ""), p_hasta: String(b?.hasta ?? ""), p_ejercicio: Number(b?.ejercicio), p_importe: Number(b?.importe), p_motivo: String(b?.motivo ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ reasignado: true });
}
