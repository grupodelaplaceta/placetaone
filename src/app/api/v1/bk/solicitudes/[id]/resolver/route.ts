import { clientFrom } from "@/lib/apikey";

// Resolver una solicitud (solicitudes:gestionar). decision: concedida | denegada. No puede resolverla quien la pidió.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "solicitudes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const actorRes = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return Response.json({ error: actorRes.error.message }, { status: 422 });
  const { error } = await a.db.rpc("plone27_solicitud_resolver", { p_bank: a.c.bank_id, p_solicitud: id, p_actor: actorRes.data,
    p_decision: String(b?.decision ?? ""), p_resolucion: String(b?.resolucion ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ resuelta: true });
}
