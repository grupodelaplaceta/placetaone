import { staffFrom } from "@/lib/supabase";

// Cerrar una convocatoria (admin): no admite concesiones nuevas. Resuelve la entidad y el banco desde la propia convocatoria.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { id } = await params;
  const cv = await s.db.from("plone27_convocatorias").select("entidad").eq("id", id).maybeSingle();
  if (!cv.data) return Response.json({ error: "Convocatoria no encontrada" }, { status: 404 });
  const ent = await s.db.from("plone27_entidades").select("cip").eq("account_id", cv.data.entidad as string).maybeSingle();
  const acc = await s.db.from("plone27_accounts").select("bank_id").eq("id", cv.data.entidad as string).maybeSingle();
  if (!ent.data || !acc.data) return Response.json({ error: "La entidad de la convocatoria no existe" }, { status: 422 });
  const { error } = await s.db.rpc("plone27_convocatoria_cerrar", { p_bank: acc.data.bank_id as string, p_cip: ent.data.cip as string, p_conv: id, p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ cerrada: true });
}
