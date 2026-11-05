import { clientFrom } from "@/lib/apikey";

// Dar de alta un titular, autorizado o lector en una empresa (empresas:gestionar).
// Body: { dip, rol: "titular" | "autorizado" | "lector", motivo, dip_actor: DIP de un titular de la empresa }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const persona = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip ?? "") });
  if (persona.error) return Response.json({ error: persona.error.message }, { status: 422 });
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_empresa_titular_alta", { p_bank: a.c.bank_id, p_empresa: id, p_persona: persona.data,
    p_rol: String(b?.rol ?? ""), p_motivo: String(b?.motivo ?? ""), p_actor: actor.data });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ titular: data }, { status: 201 });
}
