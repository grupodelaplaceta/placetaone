import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Comprar un diseño desde una cuenta propia. Body: { iban }. Idempotency-Key obligatoria.
export async function POST(req: Request, { params }: { params: Promise<{ codigo: string }> }) {
  const r = await sesionDe(req, "me:transfer");
  if ("err" in r) return r.err;
  const { s } = r;
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return respuesta(req, { error: "Idempotency-Key obligatoria (máximo 128)" }, 400, s.cliente);
  const { codigo } = await params;
  const b = await req.json().catch(() => null);
  const { data, error } = await s.db.rpc("plone27_user_diseno_comprar", {
    p_user: s.usuario, p_bank: s.banco, p_codigo: codigo, p_iban: String(b?.iban ?? ""),
    p_key: `diseno:${s.cliente}:${s.usuario}:${clave}`,
  });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { transaccion: data }, 201, s.cliente);
}
