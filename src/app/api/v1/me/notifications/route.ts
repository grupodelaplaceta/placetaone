import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Notificaciones del usuario. ?solo_nuevas=1&limite=50
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const u = new URL(req.url);
  const { data, error } = await s.db.rpc("plone27_user_notifications", {
    p_user: s.usuario, p_bank: s.banco, p_solo_nuevas: u.searchParams.get("solo_nuevas") === "1", p_limite: Number(u.searchParams.get("limite") ?? 50) });
  if (error) return respuesta(req, { error: "No se pueden cargar las notificaciones" }, 422, s.cliente);
  return respuesta(req, { notificaciones: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
