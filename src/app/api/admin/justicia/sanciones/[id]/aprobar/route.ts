import { staffFrom } from "@/lib/supabase";

// aprobar una sanción (solo la Junta). Otra persona de la Junta distinta de quien propuso.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_sancion_aprobar", { p_id: id, p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data ?? { ok: true });
}
