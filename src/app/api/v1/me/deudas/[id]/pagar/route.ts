import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Pagar una deuda (me:transfer). Cabecera Idempotency-Key obligatoria. Body: { importe }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const r = await sesionDe(req, "me:transfer");
  if ("err" in r) return r.err;
  const { s } = r;
  const { id } = await params;
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{8,80}$/.test(clave)) return respuesta(req, { error: "Idempotency-Key obligatoria (8 a 80 caracteres)" }, 400, s.cliente);
  const b = await req.json().catch(() => null);
  const importe = Number(b?.importe);
  if (!(importe > 0)) return respuesta(req, { error: "Importe no válido" }, 400, s.cliente);
  const { data, error } = await s.db.rpc("plone27_user_debt_pay", { p_user: s.usuario, p_bank: s.banco, p_debt: id, p_amount: importe, p_key: `deuda-api:${s.usuario}:${clave}` });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { transaccion: data }, 200, s.cliente);
}
