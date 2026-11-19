import { clientFrom } from "@/lib/apikey";

// Contratos de nómina de tu entidad (solo lectura). Permiso: nominas:read
export async function GET(req: Request) {
  const a = await clientFrom(req, "nominas:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_nominas", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden cargar las nóminas" }, { status: 422 });
  return Response.json({ nominas: Array.isArray(data) ? data : [] });
}
