import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Próximos movimientos del usuario (impuestos, cuotas, nóminas, programadas, deudas, RBU). ?desde=&hasta= (máximo 366 días)
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const u = new URL(req.url);
  const hoy = new Date();
  const desde = u.searchParams.get("desde") ?? hoy.toISOString().slice(0, 10);
  const hasta = u.searchParams.get("hasta") ?? new Date(hoy.getTime() + 30 * 864e5).toISOString().slice(0, 10);
  const dias = (new Date(hasta).getTime() - new Date(desde).getTime()) / 864e5;
  if (Number.isNaN(dias) || dias < 0 || dias > 366) return respuesta(req, { error: "Rango de fechas no válido (máximo 366 días)" }, 400, s.cliente);
  const { data, error } = await s.db.rpc("plone27_user_previsiones", { p_user: s.usuario, p_bank: s.banco, p_desde: desde, p_hasta: hasta });
  if (error) return respuesta(req, { error: "No se puede cargar la previsión" }, 422, s.cliente);
  return respuesta(req, { desde, hasta, previsiones: Array.isArray(data) ? data : [] }, 200, s.cliente);
}
