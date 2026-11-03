import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Saldo RBU del usuario en su tarjeta prepago, por asignación y fecha de caducidad
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_rbu_saldo", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se puede cargar el saldo RBU" }, 422, s.cliente);
  const saldo = Array.isArray(data) ? data : [];
  const total = saldo.reduce((acc: number, x: { importe: number }) => acc + Number(x.importe), 0);
  return respuesta(req, { saldo, total }, 200, s.cliente);
}
