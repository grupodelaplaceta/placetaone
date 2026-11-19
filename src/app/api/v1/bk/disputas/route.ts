import { clientFrom } from "@/lib/apikey";

// Reclamaciones de deudas que afectan a la entidad: como acreedor (debe devolver) o como deudor (disputas:gestionar)
export async function GET(req: Request) {
  const a = await clientFrom(req, "disputas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_disputas", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden listar las reclamaciones" }, { status: 422 });
  return Response.json({ disputas: data ?? [] });
}
