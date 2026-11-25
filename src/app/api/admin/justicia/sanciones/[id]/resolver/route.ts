import { staffFrom } from "@/lib/supabase";

// resolver una sanción (solo la Junta). Body: { confirmar: true|false }. Otra persona de la Junta.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_sancion_resolver_recurso", { p_id: id, p_confirmar: b?.confirmar === true, p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data ?? { ok: true });
}
