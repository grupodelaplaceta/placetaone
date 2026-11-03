import { clientFrom, hexAleatorio } from "@/lib/apikey";

// Crear un pago de la pasarela (checkout:crear). Devuelve un código de pago que el cliente introduce en la app de su banco.
// El banco del pagador canjea el código (POST /api/v1/bk/pagos/canjear) y aprueba o rechaza (POST /api/v1/bk/pagos/{id}/resolucion).
const PUBLICA = process.env.PLACETA_PUBLIC_URL ?? "https://placetaone.vercel.app";

// Código con formato PAG-XXXX-XXXX-XXXX-XXXX (64 bits de entropía)
function codigoPago(): string {
  const hex = hexAleatorio(8).toUpperCase();
  return `PAG-${hex.slice(0, 4)}-${hex.slice(4, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}`;
}

export async function POST(req: Request) {
  const a = await clientFrom(req, "checkout:crear");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const token = hexAleatorio(32);
  const codigo = codigoPago();
  const { data, error } = await a.db.rpc("plone27_checkout_create", {
    p_client: a.c.id, p_bank: a.c.bank_id,
    p_origen: String(b?.origen ?? ""), p_client_ref: String(b?.client_ref ?? ""), p_dip: String(b?.dip ?? ""),
    p_iban_pagador: b?.iban_pagador ? String(b.iban_pagador) : null,
    p_tarjeta_ref: b?.tarjeta_ref ? String(b.tarjeta_ref) : null,
    p_iban_destino: String(b?.iban_destino ?? ""),
    p_importe: Number(b?.importe), p_concepto: String(b?.concepto ?? ""),
    p_token: token, p_codigo_pago: codigo, p_minutos: b?.minutos == null ? 15 : Number(b.minutos),
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ id: data.id, expira: data.expira, comision: data.comision, total: data.total, aviso: data.aviso,
    codigo_pago: codigo, url: `${PUBLICA}/pagar/${token}` }, { status: 201 });
}

// Listado de los pagos de este cliente (checkout:crear). Query: estado?, limite? (máximo 200)
export async function GET(req: Request) {
  const a = await clientFrom(req, "checkout:crear");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const u = new URL(req.url);
  const { data, error } = await a.db.rpc("plone27_bk_checkouts_lista", { p_client: a.c.id, p_estado: u.searchParams.get("estado"), p_limite: Number(u.searchParams.get("limite") ?? 50) });
  if (error) return Response.json({ error: "No se pueden listar los pagos" }, { status: 422 });
  return Response.json({ pagos: data ?? [] });
}
