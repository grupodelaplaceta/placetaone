import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Bonos de la RBU del usuario (disponibles, reclamados o caducados)
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_rbu_list", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar los bonos" }, 422, s.cliente);
  return respuesta(req, { bonos: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
