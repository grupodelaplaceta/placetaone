import { clientFrom } from "@/lib/apikey";

// Catálogo de diseños para tu entidad (generales + los tuyos). Permiso: products:read. Solo servidor.
export async function GET(req: Request) {
  const a = await clientFrom(req, "products:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_catalogo_disenos", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se puede cargar el catálogo" }, { status: 422 });
  return Response.json({ disenos: Array.isArray(data) ? data : [] });
}
