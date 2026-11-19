import { clientFrom } from "@/lib/apikey";

// Vincular una entidad institucional (CIP) a la empresa (empresas:gestionar). Lo pide un titular de la empresa.
// Body: { cip: "CIP-00000001", dip_actor }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { error } = await a.db.rpc("plone27_empresa_vincular_entidad", { p_bank: a.c.bank_id, p_empresa: id, p_cip: String(b?.cip ?? ""), p_actor: actor.data });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ vinculada: true });
}
