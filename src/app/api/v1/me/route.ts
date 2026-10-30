import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Datos de la sesión: entidad y permisos concedidos
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data } = await s.db.from("plone27_banks").select("code,name").eq("id", s.banco).maybeSingle();
  return respuesta(req, { banco: data ? { codigo: data.code, nombre: data.name } : null, permisos: s.permisos }, 200, s.cliente);
}
