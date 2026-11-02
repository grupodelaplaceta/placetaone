import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Transferencia ordenada por el usuario desde una cuenta suya. Idempotency-Key obligatoria.
export async function POST(req: Request) {
  const r = await sesionDe(req, "me:transfer");
  if ("err" in r) return r.err;
  const { s } = r;
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return respuesta(req, { error: "Idempotency-Key obligatoria (máximo 128)" }, 400, s.cliente);
  let b: { desde_iban?: unknown; hacia_iban?: unknown; importe?: unknown; concepto?: unknown };
  try { b = await req.json(); } catch { return respuesta(req, { error: "JSON no válido" }, 400, s.cliente); }
  const importe = Number(b.importe);
  if (!Number.isFinite(importe) || importe <= 0) return respuesta(req, { error: "importe debe ser mayor que cero" }, 400, s.cliente);
  const { data, error } = await s.db.rpc("plone27_user_transfer", {
    p_key: `me:${s.cliente}:${s.usuario}:${clave}`, p_user: s.usuario,
    p_from_iban: String(b.desde_iban ?? ""), p_to_iban: String(b.hacia_iban ?? ""),
    p_amount: importe, p_memo: typeof b.concepto === "string" ? b.concepto.slice(0, 200) : null, p_bank: s.banco });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { transaccion: data }, 201, s.cliente);
}
