import { clientFrom } from "@/lib/apikey";

// Generar y pagar la nómina de un periodo (nominas:generar). Body: cip, periodo (AAAA-MM), dip_actor.
// Si un pago no tiene presupuesto, no se paga ninguno del lote.
export async function POST(req: Request) {
  const a = await clientFrom(req, "nominas:generar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_nomina_periodo", { p_bank: a.c.bank_id, p_cip: String(b?.cip ?? ""), p_actor: actor.data, p_periodo: String(b?.periodo ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}
