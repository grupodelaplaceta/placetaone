import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Solicitudes del usuario (préstamo o cuenta). Quedan pendientes hasta que el personal las resuelva.
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
  const { data, error } = await s.db.rpc("plone27_user_request_create", {
    p_user: s.usuario, p_bank: s.banco, p_tipo: String(b?.tipo ?? ""), p_importe: b?.importe == null ? null : Number(b.importe),
    p_cuotas: b?.cuotas == null ? null : Number(b.cuotas), p_motivo: typeof b?.motivo === "string" ? b.motivo : null,
    p_clave: `me:${s.cliente}:${s.usuario}:${clave}` });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { solicitud: data }, 201, s.cliente);
}
