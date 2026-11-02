import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;
import { hashKey } from "@/lib/apikey";

// Sesiones del usuario (sin tokens): dónde tiene abierta la cuenta
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_sessions_list", { p_user: s.usuario });
  if (error) return respuesta(req, { error: "No se pueden cargar las sesiones" }, 422, s.cliente);
  return respuesta(req, { sesiones: Array.isArray(data) ? data : [] }, 200, s.cliente);
}

// Cerrar todas las sesiones excepto la actual (cambio de contraseña o sospecha de acceso)
export async function DELETE(req: Request) {
  const r = await sesionDe(req, "me:seguridad");
  if ("err" in r) return r.err;
  const { s } = r;
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer /, "");
  const { data, error } = await s.db.rpc("plone27_user_sessions_revoke_others", { p_user: s.usuario, p_hash_actual: hashKey(token) });
  if (error) return respuesta(req, { error: "No se pueden cerrar las sesiones" }, 422, s.cliente);
  return respuesta(req, { cerradas: data ?? 0 }, 200, s.cliente);
}
