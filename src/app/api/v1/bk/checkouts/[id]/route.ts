import { clientFrom } from "@/lib/apikey";

// Estado de un pago de tu cliente. Nunca devuelve el código ni el token.
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "checkout:crear");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { data, error } = await a.db.rpc("plone27_bk_checkout_get", { p_client: a.c.id, p_id: id });
  if (error) return Response.json({ error: "No se puede consultar" }, { status: 422 });
  if (!data) return Response.json({ error: "No encontrado" }, { status: 404 });
  return Response.json(data);
}
