import { staffFrom } from "@/lib/supabase";

// Tarifa de comisiones interbancarias por banco (propietario de la pasarela). Solo aprobador.
// Body: { bank_id, beneficiario: "propietario" | "banco_pagador", tipo: "fijo" | "porcentaje", valor }
export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const { error } = await s.db.rpc("plone27_admin_comision_set", { p_bank: String(b?.bank_id ?? ""), p_beneficiario: String(b?.beneficiario ?? ""),
    p_tipo: String(b?.tipo ?? ""), p_valor: Number(b?.valor) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ ok: true });
}
