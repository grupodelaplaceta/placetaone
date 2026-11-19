import { clientFrom } from "@/lib/apikey";

// Dar de baja un webhook (webhooks:gestionar)
export async function DELETE(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "webhooks:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { error } = await a.db.rpc("plone27_bk_webhook_baja", { p_bank: a.c.bank_id, p_id: id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ dado_de_baja: true });
}
