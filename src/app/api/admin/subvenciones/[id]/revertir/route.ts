import { staffFrom } from "@/lib/supabase";

// Revertir un abono (justificacion) o toda la subvención (admin). Body: { motivo (>=10), justificacion? }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_grant_revertir", {
    p_grant: id, p_just: b?.justificacion ? String(b.justificacion) : null, p_motivo: String(b?.motivo ?? ""), p_actor: s.id, p_bank: null,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}
