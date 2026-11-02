import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Catálogo de diseños disponibles para el usuario en su entidad
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_catalogo", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se puede cargar el catálogo" }, 422, s.cliente);
  return respuesta(req, { disenos: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
