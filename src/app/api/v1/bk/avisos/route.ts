import { clientFrom } from "@/lib/apikey";

// Avisos que el banco debe enviar a sus clientes (avisos:gestionar). Solo los ya visibles.
// El banco los envía con su propio Gmail y acusa recibo con POST /api/v1/bk/avisos/{id}/acuse.
export async function GET(req: Request) {
  const a = await clientFrom(req, "avisos:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_avisos_pendientes", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ avisos: data ?? [] });
}
