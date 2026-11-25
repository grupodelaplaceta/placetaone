import { staffFrom } from "@/lib/supabase";

// recurrir una sanción (solo la Junta). Registra el recurso. Body: { motivo }.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_sancion_recurrir", { p_id: id, p_motivo: String(b?.motivo ?? ""), p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data ?? { ok: true });
}
