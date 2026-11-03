import { clientFrom } from "@/lib/apikey";

// Liquidar un cargo autorizado (débito: cobra; crédito: pasa a facturado). Idempotency-Key obligatoria.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "tarjetas:cobrar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return Response.json({ error: "Idempotency-Key obligatoria (máximo 128)" }, { status: 400 });
  const { id } = await params;
  const { data, error } = await a.db.rpc("plone27_bk_card_settle", { p_bank: a.c.bank_id, p_charge: id, p_key: `bk:${a.c.id}:liquidar:${clave}` });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}
