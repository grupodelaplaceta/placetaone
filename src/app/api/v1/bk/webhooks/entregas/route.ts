import { clientFrom } from "@/lib/apikey";

// Últimos eventos enviados a la entidad y su estado de entrega (webhooks:gestionar)
export async function GET(req: Request) {
  const a = await clientFrom(req, "webhooks:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_outbox").select("id,event,status").contains("bank_ids", [a.c.bank_id]).order("id", { ascending: false }).limit(100);
  if (error) return Response.json({ error: "No se puede consultar" }, { status: 422 });
  return Response.json({ entregas: data ?? [] });
}
