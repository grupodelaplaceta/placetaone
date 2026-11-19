import { clientFrom } from "@/lib/apikey";

// Liberar un cargo autorizado que no se va a liquidar. Solo se libera una vez.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "tarjetas:cobrar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { data, error } = await a.db.rpc("plone27_bk_card_release", { p_bank: a.c.bank_id, p_charge: id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}
