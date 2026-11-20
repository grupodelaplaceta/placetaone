import { staffFrom } from "@/lib/supabase";

// Decide si lo recuperado de una deuda por reversión se vuelve a autorizar en esta convocatoria (admin). Body: { reautoriza_recuperados: boolean }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  if (typeof b?.reautoriza_recuperados !== "boolean") return Response.json({ error: "reautoriza_recuperados debe ser true o false" }, { status: 400 });
  const { error } = await s.db.rpc("plone27_convocatoria_reautorizacion_fijar", { p_conv: id, p_valor: b.reautoriza_recuperados, p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ ok: true });
}
