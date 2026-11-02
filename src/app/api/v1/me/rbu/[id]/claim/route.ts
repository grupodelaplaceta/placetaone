import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Reclamar un bono de la RBU (el titular lo reclama; no se cobra solo). Idempotency-Key obligatoria.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const r = await sesionDe(req, "me:transfer");
  if ("err" in r) return r.err;
  const { s } = r;
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return respuesta(req, { error: "Idempotency-Key obligatoria (máximo 128)" }, 400, s.cliente);
  const { id } = await params;
  const { data, error } = await s.db.rpc("plone27_user_rbu_claim", { p_user: s.usuario, p_bank: s.banco, p_bonus: id, p_key: `me:${s.cliente}:${s.usuario}:${clave}` });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { transaccion: data }, 201, s.cliente);
}
