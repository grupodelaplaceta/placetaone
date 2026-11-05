import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Reclamaciones del usuario sobre sus deudas (me:read)
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_disputas", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar las reclamaciones" }, 422, s.cliente);
  return respuesta(req, { disputas: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
