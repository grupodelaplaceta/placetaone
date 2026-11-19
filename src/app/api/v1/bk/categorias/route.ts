import { clientFrom } from "@/lib/apikey";
// Categorías de comercio que asigna Placeta (politicas:gestionar)
export async function GET(req: Request) {
  const a = await clientFrom(req, "politicas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_categorias", {});
  if (error) return Response.json({ error: "No se pueden listar las categorías" }, { status: 422 });
  return Response.json({ categorias: data ?? [] });
}
