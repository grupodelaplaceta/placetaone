import { clientFrom, codigoVerificacion, hexAleatorio } from "@/lib/apikey";

// Crear un pago en la pasarela. Solo servidor. Permiso: checkout:crear.
// Body: { origen, client_ref, dip, iban_pagador, iban_destino, importe, concepto, minutos? }
// Devuelve la URL de la ventana de pago. El código de verificación NO se devuelve aquí: llega por webhook (checkout.codigo).
const PUBLICA = process.env.PLACETA_PUBLIC_URL ?? "https://placetaone.vercel.app";

export async function POST(req: Request) {
  const a = await clientFrom(req, "checkout:crear");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const token = hexAleatorio(32);
  const codigo = codigoVerificacion();
  const { data, error } = await a.db.rpc("plone27_checkout_create", {
    p_client: a.c.id, p_bank: a.c.bank_id,
    p_origen: String(b?.origen ?? ""), p_client_ref: String(b?.client_ref ?? ""), p_dip: String(b?.dip ?? ""),
    p_iban_pagador: String(b?.iban_pagador ?? ""), p_iban_destino: String(b?.iban_destino ?? ""),
    p_importe: Number(b?.importe), p_concepto: String(b?.concepto ?? ""),
    p_token: token, p_codigo: codigo, p_minutos: b?.minutos == null ? 15 : Number(b.minutos),
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ id: data.id, expira: data.expira, url: `${PUBLICA}/pagar/${token}` }, { status: 201 });
}
