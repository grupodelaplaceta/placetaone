import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Deudas de las cuentas a las que el usuario tiene acceso (me:read)
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_debts", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar las deudas" }, 422, s.cliente);
  return respuesta(req, { deudas: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
