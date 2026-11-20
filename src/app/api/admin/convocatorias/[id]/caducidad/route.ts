import { staffFrom } from "@/lib/supabase";

// Fijar la caducidad de los bonos de una convocatoria (admin). Body: { caduca: "AAAA-MM-DD" | null }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { error } = await s.db.rpc("plone27_convocatoria_caducidad_fijar", { p_conv: id, p_caduca: b?.caduca ? String(b.caduca) : null, p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ ok: true });
}
