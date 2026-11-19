import { clientFrom, hashKey, hexAleatorio } from "@/lib/apikey";

// Rotar la clave de una clave de API de la entidad (clientes:gestionar). La anterior deja de funcionar.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "clientes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const clave = "plk_" + hexAleatorio(24);
  const { data, error } = await a.db.from("plone27_api_clients").update({ key_hash: hashKey(clave) }).eq("id", id).eq("bank_id", a.c.bank_id).select("id");
  if (error) return Response.json({ error: "No se puede rotar la clave" }, { status: 422 });
  if (!data || data.length === 0) return Response.json({ error: "Clave no encontrada en tu entidad" }, { status: 404 });
  return Response.json({ api_key: clave, aviso: "Guarda la clave ahora: no se vuelve a mostrar. La anterior ya no funciona." });
}
