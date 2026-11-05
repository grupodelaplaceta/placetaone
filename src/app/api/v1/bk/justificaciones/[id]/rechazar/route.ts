import { clientFrom } from "@/lib/apikey";
// Rechazar una justificación pendiente (subvenciones:gestionar). Body: { motivo }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const { error } = await a.db.rpc("plone27_bk_justificacion_rechazar", { p_bank: a.c.bank_id, p_just: id, p_motivo: String(b?.motivo ?? ""), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ rechazada: true });
}
