import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Cuentas del usuario de la sesión (solo las suyas)
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_accounts", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar las cuentas" }, 500, s.cliente);
  const cuentas = (Array.isArray(data) ? data : []).map(({ id: _id, ...resto }) => resto);
  return respuesta(req, { cuentas }, 200, s.cliente);
}
