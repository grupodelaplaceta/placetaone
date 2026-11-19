import { sesionDe, respuesta, preflight, cuentaDelUsuario } from "@/lib/sesion";
export const OPTIONS = preflight;

// Recibos fiscales de una cuenta del usuario
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { iban } = await params;
  const cuenta = await cuentaDelUsuario(s, iban);
  if (!cuenta) return respuesta(req, { error: "Cuenta no encontrada" }, 404, s.cliente);
  const { data, error } = await s.db.rpc("plone27_user_receipts", { p_user: s.usuario, p_account: cuenta, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar los recibos" }, 422, s.cliente);
  return respuesta(req, { recibos: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
