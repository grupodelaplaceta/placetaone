import { clientFrom } from "@/lib/apikey";

// Autorizar un pago recurrente de una unidad (recurrentes:gestionar).
export async function POST(req: Request) {
  const a = await clientFrom(req, "recurrentes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actorRes = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return Response.json({ error: actorRes.error.message }, { status: 422 });
  const cip = String(b?.cip ?? "");
  const { data, error } = await a.db.rpc("plone27_recurrente_crear", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data,
    p_unidad: String(b?.unidad ?? ""), p_concepto: String(b?.concepto ?? ""), p_importe: Number(b?.importe), p_iban: b?.iban ? String(b.iban) : null,
    p_meses: Number(b?.meses), p_desde: String(b?.desde ?? ""), p_hasta: b?.hasta ? String(b.hasta) : null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ recurrente: data }, { status: 201 });
}
