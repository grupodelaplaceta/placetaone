import { clientFrom } from "@/lib/apikey";

// Cuentas de la entidad con saldo disponible (accounts:read)
export async function GET(req: Request) {
  const a = await clientFrom(req, "accounts:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_cuentas", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden listar las cuentas" }, { status: 422 });
  return Response.json({ cuentas: data ?? [] });
}
