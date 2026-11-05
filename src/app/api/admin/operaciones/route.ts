import { staffFrom } from "@/lib/supabase";

// Pagos, operaciones interbancarias, restricciones y comisiones de una entidad.
// Lectura: personal de gestión. Cambios (aprobador): restricciones de pago y tarifa de comisiones interbancarias.
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const u = new URL(req.url);
  const bank = u.searchParams.get("bank_id") ?? "";
  const vista = u.searchParams.get("vista") ?? "pagos";
  const hoy = new Date();
  const desde = u.searchParams.get("desde") ?? new Date(hoy.getTime() - 30 * 864e5).toISOString().slice(0, 10);
  const hasta = u.searchParams.get("hasta") ?? hoy.toISOString().slice(0, 10);
  if (vista === "pagos") {
    const { data, error } = await s.db.from("plone27_checkouts")
      .select("id,client_ref,estado,importe,comision,medio,interbancaria,creada,resuelta,bank_id,banco_pagador")
      .or(`bank_id.eq.${bank},banco_pagador.eq.${bank}`).order("creada", { ascending: false }).limit(100);
    return error ? Response.json({ error: error.message }, { status: 500 }) : Response.json({ pagos: data ?? [] });
  }
  if (vista === "interbancarias") {
    const { data, error } = await s.db.rpc("plone27_interbancarias", { p_bank: bank, p_desde: desde, p_hasta: hasta });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ operaciones: data ?? [] });
  }
  if (vista === "reglas") {
    const [restr, com, pol] = await Promise.all([
      s.db.from("plone27_restricciones_pago").select("tipo,valor,bloqueado").eq("bank_id", bank),
      s.db.from("plone27_comisiones_banco").select("beneficiario,tipo,valor").eq("bank_id", bank).maybeSingle(),
      s.db.from("plone27_politica_comision").select("producto,pagador").eq("bank_id", bank),
    ]);
    const error = restr.error || com.error || pol.error;
    return error ? Response.json({ error: error.message }, { status: 500 })
      : Response.json({ restricciones: restr.data ?? [], comision: com.data ?? null, politica: pol.data ?? [] });
  }
  return Response.json({ error: "Vista no válida" }, { status: 400 });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const bank = String(b?.bank_id ?? "");
  const fail = (m: string) => Response.json({ error: m }, { status: 422 });
  if (b?.accion === "restriccion") {
    const { error } = await s.db.rpc("plone27_bk_restriccion_set", { p_bank: bank, p_tipo: String(b?.tipo ?? ""), p_valor: String(b?.valor ?? ""), p_bloqueado: Boolean(b?.bloqueado) });
    return error ? fail(error.message) : Response.json({ ok: true });
  }
  if (b?.accion === "comision") {
    const { error } = await s.db.rpc("plone27_admin_comision_set", { p_bank: bank, p_beneficiario: String(b?.beneficiario ?? ""), p_tipo: String(b?.tipo ?? ""), p_valor: Number(b?.valor) });
    return error ? fail(error.message) : Response.json({ ok: true });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
