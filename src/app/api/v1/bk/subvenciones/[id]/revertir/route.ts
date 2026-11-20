import { clientFrom } from "@/lib/apikey";
import { personaPorDip } from "@/lib/empresas";
import { subvencionDeBanco } from "@/lib/subvenciones";

// El subvencionante revierte un abono o toda la subvención (subvenciones:gestionar).
// Body: { motivo (>=10), justificacion?, dip_actor }. Requiere permiso de ejecutar en la entidad (o ser la Junta).
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  if (!(await subvencionDeBanco(a.db, a.c.bank_id, id))) return Response.json({ error: "Subvención no encontrada en tu entidad" }, { status: 404 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { data, error } = await a.db.rpc("plone27_grant_revertir", {
      p_grant: id, p_just: b?.justificacion ? String(b.justificacion) : null, p_motivo: String(b?.motivo ?? ""), p_actor: actor, p_bank: a.c.bank_id,
    });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json(data);
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
