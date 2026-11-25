import { clientFrom } from "@/lib/apikey";

// Denuncia de la persona sancionada (o su tutor) a través de su banco (justicia:denunciar).
// Es la única vía de recurso. Body: { dip, texto } (texto de al menos 20 caracteres).
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "justicia:denunciar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await a.db.rpc("plone27_sancion_denunciar", {
    p_bank: a.c.bank_id, p_sancion: id, p_dip: String(b?.dip ?? ""), p_texto: String(b?.texto ?? ""), p_actor: null,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ denuncia: data }, { status: 201 });
}
