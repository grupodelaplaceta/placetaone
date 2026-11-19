import { clientFrom } from "@/lib/apikey";

// Política de comisiones del banco: quién paga la comisión en cuentas y en tarjetas (comisiones:configurar).
// La tarifa y quién la cobra los fija el propietario de la pasarela; aquí se muestran.
export async function GET(req: Request) {
  const a = await clientFrom(req, "comisiones:configurar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const pol = await a.db.from("plone27_politica_comision").select("producto,pagador").eq("bank_id", a.c.bank_id);
  const tar = await a.db.from("plone27_comisiones_banco").select("beneficiario,tipo,valor").eq("bank_id", a.c.bank_id).maybeSingle();
  if (pol.error || tar.error) return Response.json({ error: "No se puede consultar" }, { status: 422 });
  return Response.json({ politica: pol.data ?? [], tarifa: tar.data ?? null });
}

// Fijar quién paga la comisión para un producto. Body: { producto: "cuenta" | "tarjeta", pagador: "cliente" | "banco" }
export async function PUT(req: Request) {
  const a = await clientFrom(req, "comisiones:configurar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const { error } = await a.db.rpc("plone27_bk_politica_set", { p_bank: a.c.bank_id, p_producto: String(b?.producto ?? ""), p_pagador: String(b?.pagador ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ configurada: true });
}
