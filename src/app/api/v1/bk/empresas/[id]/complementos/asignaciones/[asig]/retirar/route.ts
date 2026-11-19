import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa, personaPorDip } from "@/lib/empresas";

// Retirar una asignación de complemento a partir de una fecha (retribuciones:gestionar). Body: { hasta?, dip_actor }
export async function POST(req: Request, { params }: { params: Promise<{ id: string; asig: string }> }) {
  const a = await clientFrom(req, "retribuciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id, asig } = await params;
  const b = await req.json().catch(() => null);
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { error } = await a.db.rpc("plone27_bk_complemento_retirar", { p_bank: a.c.bank_id, p_cip: c.cip, p_actor: actor, p_asignacion: asig, p_hasta: b?.hasta ? String(b.hasta) : null });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ retirada: true });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
