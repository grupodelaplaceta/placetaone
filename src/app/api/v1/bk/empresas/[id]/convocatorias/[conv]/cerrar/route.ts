import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa, personaPorDip } from "@/lib/empresas";

// Cerrar una convocatoria: no admite concesiones nuevas (subvenciones:gestionar). Body: { dip_actor }
export async function POST(req: Request, { params }: { params: Promise<{ id: string; conv: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id, conv } = await params;
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { error } = await a.db.rpc("plone27_convocatoria_cerrar", { p_bank: a.c.bank_id, p_cip: c.cip, p_conv: conv, p_actor: actor });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ cerrada: true });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
