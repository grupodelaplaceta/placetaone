import { clientFrom } from "@/lib/apikey";

// Autorizar un cargo en una tarjeta de tu entidad. Permiso: tarjetas:cobrar. Idempotency-Key obligatoria.
// Body: { card_ref, importe, iban_comercio }
export async function POST(req: Request) {
  const a = await clientFrom(req, "tarjetas:cobrar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return Response.json({ error: "Idempotency-Key obligatoria (máximo 128)" }, { status: 400 });
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_bk_card_authorize", {
    p_bank: a.c.bank_id, p_card_ref: String(b?.card_ref ?? ""), p_importe: Number(b?.importe),
    p_iban_comercio: String(b?.iban_comercio ?? ""), p_key: `bk:${a.c.id}:${clave}`,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data, { status: 201 });
}
