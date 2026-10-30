import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Planes a plazos y suscripciones del usuario
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_plans", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar los planes" }, 422, s.cliente);
  return respuesta(req, { planes: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
