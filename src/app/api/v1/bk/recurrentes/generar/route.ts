import { clientFrom } from "@/lib/apikey";

// Generar las propuestas de gasto de los pagos recurrentes de un periodo (recurrentes:gestionar).
export async function POST(req: Request) {
  const a = await clientFrom(req, "recurrentes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actorRes = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return Response.json({ error: actorRes.error.message }, { status: 422 });
  const cip = String(b?.cip ?? "");
  const { data, error } = await a.db.rpc("plone27_recurrentes_generar", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data, p_periodo: String(b?.periodo ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ propuestas: data });
}
