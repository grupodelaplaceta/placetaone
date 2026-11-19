import { staffFrom } from "@/lib/supabase";

// Tarifa propietaria de tasas por entidad: alta de tasas y baja (aprobador).
// Alta: { accion: "alta", bank_id, tipo, valor, minimo?, maximo?, medio?, client_id?, pagador: "comercio" | "banco", beneficiario: "propietario" | "banco" }
// Baja: { accion: "desactivar", bank_id, id }
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const u = new URL(req.url);
  const bankId = u.searchParams.get("bank_id") ?? "";
  if (u.searchParams.get("vista") === "posicion") {
    const hoy = new Date();
    const desde = u.searchParams.get("desde") ?? new Date(hoy.getTime() - 30 * 864e5).toISOString().slice(0, 10);
    const hasta = u.searchParams.get("hasta") ?? hoy.toISOString().slice(0, 10);
    const pos = await s.db.rpc("plone27_posicion_interbancaria", { p_bank: bankId, p_desde: desde, p_hasta: hasta });
    if (pos.error) return Response.json({ error: pos.error.message }, { status: 422 });
    return Response.json({ posicion: pos.data ?? [] });
  }
  const { data, error } = await s.db.rpc("plone27_tasas_listar", { p_bank: bankId });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ tasas: data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const bankId = String(b?.bank_id ?? "");
  if (b?.accion === "desactivar") {
    const { error } = await s.db.rpc("plone27_tasa_desactivar", { p_bank: bankId, p_id: String(b?.id ?? ""), p_actor: s.id });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ ok: true });
  }
  if (b?.accion === "alta") {
    const { data, error } = await s.db.rpc("plone27_tasa_alta", { p_bank: bankId, p_ambito: "propietario", p_client: b?.client_id ? String(b.client_id) : null,
      p_medio: b?.medio ? String(b.medio) : null, p_tipo: String(b?.tipo ?? ""), p_valor: Number(b?.valor), p_minimo: b?.minimo == null ? 0 : Number(b.minimo),
      p_maximo: b?.maximo == null ? null : Number(b.maximo), p_pagador: String(b?.pagador ?? "comercio"), p_beneficiario: String(b?.beneficiario ?? "propietario"), p_actor: s.id });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ ok: true, tasa: data });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
