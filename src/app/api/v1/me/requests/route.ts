import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Solicitudes del usuario (préstamo o cuenta). Las cuentas de producto sin crédito se abren al momento; el resto queda pendiente de revisión.
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:contratar");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_requests", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar las solicitudes" }, 422, s.cliente);
  return respuesta(req, { solicitudes: Array.isArray(data) ? data : [] }, 200, s.cliente);
}

// Crear una solicitud. Body: tipo ('prestamo' | 'cuenta'), importe, cuotas, motivo. Idempotency-Key obligatoria.
export async function POST(req: Request) {
  const r = await sesionDe(req, "me:contratar");
  if ("err" in r) return r.err;
  const { s } = r;
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return respuesta(req, { error: "Idempotency-Key obligatoria (máximo 128)" }, 400, s.cliente);
  const b = await req.json().catch(() => null);
  // Producto de cuenta: si es de cuenta sin crédito se abre al momento.
  if (b?.tipo === "cuenta" && typeof b?.product_id === "string" && /^[0-9a-f-]{36}$/i.test(b.product_id)) {
    const { data: pr, error: ePr } = await s.db.rpc("plone27_user_request_product", { p_user: s.usuario, p_bank: s.banco, p_product: b.product_id, p_motivo: typeof b?.motivo === "string" ? b.motivo : null, p_clave: `me:${s.cliente}:${s.usuario}:${clave}` });
    if (ePr) return respuesta(req, { error: ePr.message }, 422, s.cliente);
    return respuesta(req, { solicitud: pr }, 201, s.cliente);
  }
  const { data, error } = await s.db.rpc("plone27_user_request_create", {
    p_user: s.usuario, p_bank: s.banco, p_tipo: String(b?.tipo ?? ""), p_importe: b?.importe == null ? null : Number(b.importe),
    p_cuotas: b?.cuotas == null ? null : Number(b.cuotas), p_motivo: typeof b?.motivo === "string" ? b.motivo : null,
    p_clave: `me:${s.cliente}:${s.usuario}:${clave}` });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { solicitud: data }, 201, s.cliente);
}
