import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Tarjetas de una cuenta propia (sin datos sensibles: nunca el número completo)
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { iban } = await params;
  const { data, error } = await s.db.rpc("plone27_user_cards", { p_user: s.usuario, p_bank: s.banco, p_iban: iban });
  if (error) return respuesta(req, { error: "Cuenta no encontrada" }, 404, s.cliente);
  return respuesta(req, { tarjetas: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
