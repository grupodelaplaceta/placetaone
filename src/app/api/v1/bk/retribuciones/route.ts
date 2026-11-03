import { clientFrom } from "@/lib/apikey";

// Fijar una retribución fija o un complemento (retribuciones:gestionar).
// Body: cip, dip (persona retribuida), dip_actor (quien autoriza), concepto, importe, desde, hasta (opcional), motivo
export async function POST(req: Request) {
  const a = await clientFrom(req, "retribuciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const persona = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip ?? "") });
  if (persona.error) return Response.json({ error: persona.error.message }, { status: 422 });
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_retribucion_fijar", { p_bank: a.c.bank_id, p_cip: String(b?.cip ?? ""), p_actor: actor.data,
    p_persona: persona.data, p_concepto: String(b?.concepto ?? ""), p_importe: Number(b?.importe), p_desde: String(b?.desde ?? ""),
    p_hasta: b?.hasta ? String(b.hasta) : null, p_motivo: String(b?.motivo ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ retribucion: data }, { status: 201 });
}
