import { clientFrom } from "@/lib/apikey";

// Reintentar una entrega fallida de la entidad (webhooks:gestionar). Vuelve a pendiente; el envío automático la reenvía.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "webhooks:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { error } = await a.db.rpc("plone27_bk_entrega_reintentar", { p_bank: a.c.bank_id, p_id: Number(id) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ reintento_programado: true });
}
