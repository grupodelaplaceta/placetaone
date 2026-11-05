import { clientFrom } from "@/lib/apikey";
import { personaPorDip } from "@/lib/empresas";

// Cambiar el estado de una empresa (empresas:gestionar). Suspender o dar de baja desactiva su pasarela.
// Body: { estado: "activa" | "suspendida" | "baja", motivo, dip_actor }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { error } = await a.db.rpc("plone27_empresa_estado", { p_bank: a.c.bank_id, p_empresa: id, p_estado: String(b?.estado ?? ""),
      p_motivo: String(b?.motivo ?? ""), p_actor: actor });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ estado_actualizado: true });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
