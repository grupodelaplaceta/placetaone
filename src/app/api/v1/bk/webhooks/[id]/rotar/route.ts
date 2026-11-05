import { cifrarSecreto, descifrarSecreto } from "@/lib/cifrado";
import { clientFrom, hexAleatorio } from "@/lib/apikey";

// Rotar el secreto de un webhook: el anterior deja de valer. El nuevo se devuelve una sola vez (webhooks:gestionar).
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "webhooks:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const secreto = hexAleatorio(24);
  const { error } = await a.db.rpc("plone27_bk_webhook_rotar", { p_bank: a.c.bank_id, p_id: id, p_secret: cifrarSecreto(secreto) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ secreto, aviso: "Guarda el secreto ahora: no se vuelve a mostrar." });
}
