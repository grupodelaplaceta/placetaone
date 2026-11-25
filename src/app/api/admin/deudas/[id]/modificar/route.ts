import { staffFrom } from "@/lib/supabase";

// Modificar el importe pendiente de una deuda (solo la Junta).
// Body: { nuevo_pendiente, justificacion (>= 30), referencia (acuerdo de votación, único) }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_deuda_modificar", {
    p_debt: id, p_nuevo: Number(b?.nuevo_pendiente), p_justificacion: String(b?.justificacion ?? ""),
    p_referencia: String(b?.referencia ?? ""), p_actor: s.id,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}
