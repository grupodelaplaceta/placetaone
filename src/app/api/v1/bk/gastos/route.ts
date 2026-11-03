import { clientFrom } from "@/lib/apikey";

// Proponer un gasto (gastos:gestionar). Idempotency-Key obligatoria.
// Body: cip, dip_actor, unidad, ejercicio, importe, concepto, beneficiario_iban (opcional)
export async function POST(req: Request) {
  const a = await clientFrom(req, "gastos:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return Response.json({ error: "Idempotency-Key obligatoria (máximo 128)" }, { status: 400 });
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_gasto_proponer", { p_bank: a.c.bank_id, p_cip: String(b?.cip ?? ""), p_actor: actor.data,
    p_unidad: String(b?.unidad ?? ""), p_ejercicio: Number(b?.ejercicio), p_importe: Number(b?.importe), p_concepto: String(b?.concepto ?? ""),
    p_iban: b?.beneficiario_iban ? String(b.beneficiario_iban) : null, p_key: `bk:${a.c.id}:${clave}` });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ gasto: data }, { status: 201 });
}
