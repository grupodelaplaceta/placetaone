import { clientFrom } from "@/lib/apikey";

// Eventos enviados a la entidad: fecha, intentos y estado de entrega (webhooks:gestionar).
// Query: estado? (pending | sent | failed), limite? (máximo 200)
export async function GET(req: Request) {
  const a = await clientFrom(req, "webhooks:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const u = new URL(req.url);
  const { data, error } = await a.db.rpc("plone27_bk_entregas_lista", { p_bank: a.c.bank_id, p_estado: u.searchParams.get("estado"), p_limite: Number(u.searchParams.get("limite") ?? 50) });
  if (error) return Response.json({ error: "No se pueden consultar las entregas" }, { status: 422 });
  return Response.json({ entregas: data ?? [] });
}
