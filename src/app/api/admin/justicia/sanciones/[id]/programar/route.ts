import { staffFrom } from "@/lib/supabase";

// Programa la ejecución de una sanción firme. Body: { fecha } en ISO 8601, con al menos 5 horas de antelación.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_sancion_programar", { p_id: id, p_fecha: String(b?.fecha ?? ""), p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data ?? { ok: true });
}
