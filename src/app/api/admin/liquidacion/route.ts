import { staffFrom } from "@/lib/supabase";

// Liquidación interbancaria: interruptores, límites, liquidación manual, tasas de operaciones y reversiones.
// Lectura: personal de gestión. Cambios: aprobador. Una reversión la solicita una persona y la aprueba otra.
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [cfg, liq, pend, lim, rev] = await Promise.all([
    s.db.from("plone27_config_interbancaria").select("liquidacion_activa,tasas_operaciones_activas").eq("id", 1).maybeSingle(),
    s.db.from("plone27_liquidaciones").select("id,fecha,banco_deudor,banco_acreedor,importe,estado,motivo,revierte,creada").order("creada", { ascending: false }).limit(100),
    s.db.from("plone27_operaciones_interbancarias").select("id,origen,destino,importe,fecha,ref").is("liquidada_en", null).order("id", { ascending: false }).limit(200),
    s.db.from("plone27_limites_exposicion").select("bank_deudor,bank_acreedor,limite"),
    s.db.from("plone27_reversiones").select("id,liquidacion,motivo,solicitada_por,estado,creada").eq("estado", "pendiente"),
  ]);
  const error = cfg.error || liq.error || pend.error || lim.error || rev.error;
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json({ config: cfg.data ?? null, liquidaciones: liq.data ?? [], pendientes: pend.data ?? [], limites: lim.data ?? [], reversiones: rev.data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const fail = (m: string) => Response.json({ error: m }, { status: 422 });
  const acc = String(b?.accion ?? "");
  if (acc === "config") {
    const r = await s.db.rpc("plone27_config_interbancaria_set", { p_liquidacion: Boolean(b?.liquidacion), p_tasas: Boolean(b?.tasas), p_actor: s.id });
    return r.error ? fail(r.error.message) : Response.json({ ok: true });
  }
  if (acc === "liquidar") {
    const hoy = new Date().toISOString().slice(0, 10);
    const r = await s.db.rpc("plone27_liquidar", { p_fecha: String(b?.fecha ?? hoy), p_actor: s.id });
    return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
  }
  if (acc === "limite") {
    const r = await s.db.rpc("plone27_limite_set", { p_deudor: String(b?.deudor ?? ""), p_acreedor: String(b?.acreedor ?? ""), p_limite: Number(b?.limite), p_actor: s.id });
    return r.error ? fail(r.error.message) : Response.json({ ok: true });
  }
  if (acc === "tasa_operacion") {
    const r = await s.db.rpc("plone27_tasa_alta_operacion", { p_bank: String(b?.bank_id ?? ""), p_operacion: String(b?.operacion ?? ""),
      p_tipo: String(b?.tipo ?? ""), p_valor: Number(b?.valor), p_minimo: b?.minimo == null ? 0 : Number(b.minimo),
      p_maximo: b?.maximo == null ? null : Number(b.maximo), p_beneficiario: String(b?.beneficiario ?? "propietario"), p_actor: s.id });
    return r.error ? fail(r.error.message) : Response.json({ ok: true, tasa: r.data });
  }
  if (acc === "solicitar_reversion") {
    const r = await s.db.rpc("plone27_reversion_solicitar", { p_liq: String(b?.liquidacion ?? ""), p_motivo: String(b?.motivo ?? ""), p_solicitante: s.id });
    return r.error ? fail(r.error.message) : Response.json({ ok: true, solicitud: r.data });
  }
  if (acc === "aprobar_reversion") {
    const r = await s.db.rpc("plone27_reversion_aprobar", { p_id: String(b?.reversion ?? ""), p_aprobador: s.id });
    return r.error ? fail(r.error.message) : Response.json({ ok: true, compensatoria: r.data });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
