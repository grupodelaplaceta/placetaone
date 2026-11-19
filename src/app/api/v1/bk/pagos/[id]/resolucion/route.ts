import { clientFrom } from "@/lib/apikey";

// El banco pagador aprueba o rechaza un pago de su cliente (pagos:resolver).
// Body: { decision: "aprobado" | "rechazado", dip: DIP del cliente que autoriza, motivo?: string }
// Solo puede resolver pagos cuya cuenta o tarjeta pertenece a su entidad.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "pagos:resolver");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_checkout_resolver", {
    p_checkout: id, p_bank_pagador: a.c.bank_id, p_dip: String(b?.dip ?? ""),
    p_decision: String(b?.decision ?? ""), p_motivo: b?.motivo ? String(b.motivo) : null,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  if (data?.error) return Response.json({ error: data.error, estado: data.estado }, { status: 422 });
  return Response.json(data);
}
