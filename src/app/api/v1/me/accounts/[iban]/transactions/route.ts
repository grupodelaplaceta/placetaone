import { sesionDe, respuesta, preflight, cuentaDelUsuario } from "@/lib/sesion";
export const OPTIONS = preflight;

// Movimientos de una cuenta del usuario, paginados (?antes=<id>&limite=<n>)
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { iban } = await params;
  const cuenta = await cuentaDelUsuario(s, iban);
  if (!cuenta) return respuesta(req, { error: "Cuenta no encontrada" }, 404, s.cliente);
  const u = new URL(req.url);
  const antes = u.searchParams.get("antes");
  const limite = Number(u.searchParams.get("limite") ?? 50);
  const { data, error } = await s.db.rpc("plone27_user_transactions", {
    p_user: s.usuario, p_account: cuenta, p_antes: antes ? Number(antes) : null, p_limite: limite, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar los movimientos" }, 422, s.cliente);
  const movimientos = Array.isArray(data) ? data : [];
  const siguiente = movimientos.length ? movimientos[movimientos.length - 1].id : null;
  return respuesta(req, { movimientos, siguiente }, 200, s.cliente);
}
