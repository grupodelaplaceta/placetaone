import { clientFrom } from "@/lib/apikey";

// Desactivar una tasa de la entidad (tasas:gestionar). Las tasas ya cobradas no se modifican.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "tasas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { error } = await a.db.rpc("plone27_tasa_desactivar", { p_bank: a.c.bank_id, p_id: id, p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ desactivada: true });
}
