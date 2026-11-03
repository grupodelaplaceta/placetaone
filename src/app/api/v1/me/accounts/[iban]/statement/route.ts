import { sesionDe, respuesta, preflight, cuentaDelUsuario } from "@/lib/sesion";
export const OPTIONS = preflight;

// Extracto de una cuenta propia. ?desde=AAAA-MM-DD&hasta=AAAA-MM-DD (máximo 366 días)
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { iban } = await params;
  const cuenta = await cuentaDelUsuario(s, iban);
  if (!cuenta) return respuesta(req, { error: "Cuenta no encontrada" }, 404, s.cliente);
  const u = new URL(req.url);
  const hoy = new Date();
  const hasta = u.searchParams.get("hasta") ?? hoy.toISOString().slice(0, 10);
  const desde = u.searchParams.get("desde") ?? new Date(hoy.getTime() - 30 * 864e5).toISOString().slice(0, 10);
  const { data, error } = await s.db.rpc("plone27_user_statement", { p_user: s.usuario, p_bank: s.banco, p_account: cuenta, p_desde: desde, p_hasta: hasta });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, data, 200, s.cliente);
}
