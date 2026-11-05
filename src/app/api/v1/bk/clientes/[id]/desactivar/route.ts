import { clientFrom } from "@/lib/apikey";

// Desactivar una clave de API de la entidad (clientes:gestionar). No puede desactivar la clave con la que llama.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "clientes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  if (id === a.c.id) return Response.json({ error: "No puedes desactivar la clave con la que estás llamando" }, { status: 422 });
  const { data, error } = await a.db.from("plone27_api_clients").update({ active: false }).eq("id", id).eq("bank_id", a.c.bank_id).select("id");
  if (error) return Response.json({ error: "No se puede desactivar" }, { status: 422 });
  if (!data || data.length === 0) return Response.json({ error: "Clave no encontrada en tu entidad" }, { status: 404 });
  return Response.json({ desactivada: true });
}
