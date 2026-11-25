import { clientFrom } from "@/lib/apikey";

// Registrar una denuncia presentada ante Justicia (justicia:denunciar, solo el cliente de Justicia).
// Abre el recurso de la sanción. Body: { sancion, dip, texto } (texto de al menos 20 caracteres).
export async function POST(req: Request) {
  const a = await clientFrom(req, "justicia:denunciar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await a.db.rpc("plone27_sancion_denunciar", {
    p_bank: a.c.bank_id, p_sancion: String(b?.sancion ?? ""), p_dip: String(b?.dip ?? ""), p_texto: String(b?.texto ?? ""), p_actor: null,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ denuncia: data }, { status: 201 });
}
