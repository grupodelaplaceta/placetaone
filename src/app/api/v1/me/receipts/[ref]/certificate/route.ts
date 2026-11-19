import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Certificado de cálculo de un recibo propio: norma, base, tramos, importe y cadena de huellas
export async function GET(req: Request, { params }: { params: Promise<{ ref: string }> }) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { ref } = await params;
  const { data, error } = await s.db.rpc("plone27_user_receipt_certificate", { p_user: s.usuario, p_bank: s.banco, p_ref: ref });
  if (error || !data) return respuesta(req, { error: "Recibo no encontrado" }, 404, s.cliente);
  return respuesta(req, data, 200, s.cliente);
}
