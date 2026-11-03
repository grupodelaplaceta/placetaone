import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Transferencias programadas del usuario (activas)
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_scheduled_list", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar las programaciones" }, 422, s.cliente);
  return respuesta(req, { programadas: Array.isArray(data) ? data : [] }, 200, s.cliente);
}

// Programar una transferencia. Body: desde_iban, hacia_iban, importe, fecha (ISO), periodicidad_dias (0 o vacío = única).
// Idempotency-Key obligatoria: un reintento no crea otra programación.
export async function POST(req: Request) {
  const r = await sesionDe(req, "me:transfer");
  if ("err" in r) return r.err;
  const { s } = r;
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return respuesta(req, { error: "Idempotency-Key obligatoria (máximo 128)" }, 400, s.cliente);
  let b: { desde_iban?: unknown; hacia_iban?: unknown; importe?: unknown; fecha?: unknown; periodicidad_dias?: unknown; concepto?: unknown };
  try { b = await req.json(); } catch { return respuesta(req, { error: "JSON no válido" }, 400, s.cliente); }
  const importe = Number(b.importe);
  if (!Number.isFinite(importe) || importe <= 0) return respuesta(req, { error: "importe debe ser mayor que cero" }, 400, s.cliente);
  const fecha = new Date(String(b.fecha ?? ""));
  if (Number.isNaN(fecha.getTime())) return respuesta(req, { error: "fecha no válida (ISO 8601)" }, 400, s.cliente);
  const dias = b.periodicidad_dias === undefined || b.periodicidad_dias === null ? 0 : Number(b.periodicidad_dias);
  if (!Number.isInteger(dias) || dias < 0 || dias > 366) return respuesta(req, { error: "periodicidad_dias entre 0 y 366" }, 400, s.cliente);
  const { data, error } = await s.db.rpc("plone27_user_scheduled_create", {
    p_user: s.usuario, p_bank: s.banco, p_from_iban: String(b.desde_iban ?? ""), p_to_iban: String(b.hacia_iban ?? ""),
    p_amount: importe, p_run_at: fecha.toISOString(), p_recurrence: dias > 0 ? `${dias} days` : null,
    p_memo: typeof b.concepto === "string" ? b.concepto.slice(0, 200) : null,
    p_clave: `me:${s.cliente}:${s.usuario}:${clave}` });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { programada: data }, 201, s.cliente);
}
