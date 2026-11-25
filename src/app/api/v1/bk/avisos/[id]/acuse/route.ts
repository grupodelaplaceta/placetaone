import { clientFrom } from "@/lib/apikey";

// Acuse de recibo aviso (avisos:gestionar). Así no vuelve a aparecer como pendiente.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "avisos:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { error } = await a.db.rpc("plone27_aviso_acusar", { p_bank: a.c.bank_id, p_aviso: id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ ok: true });
}
