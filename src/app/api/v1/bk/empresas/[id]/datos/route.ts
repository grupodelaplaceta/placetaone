import { clientFrom } from "@/lib/apikey";

// Corregir nombre e identificador de la empresa (empresas:gestionar). El identificador es el CIP de la entidad. Lo pide un titular activo.
// Body: { nombre, identificador_fiscal, dip_actor }
export async function PUT(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { error } = await a.db.rpc("plone27_empresa_datos_set", { p_bank: a.c.bank_id, p_empresa: id, p_nombre: String(b?.nombre ?? ""),
    p_fiscal: String(b?.identificador_fiscal ?? ""), p_actor: actor.data });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ actualizada: true });
}
