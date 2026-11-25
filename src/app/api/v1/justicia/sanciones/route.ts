import { clientFrom } from "@/lib/apikey";

// Sanciones notificadas de una persona, para que Justicia sepa qué puede denunciar (justicia:denunciar).
// Query: dip
export async function GET(req: Request) {
  const a = await clientFrom(req, "justicia:denunciar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const dip = new URL(req.url).searchParams.get("dip") ?? "";
  const { data, error } = await a.db.rpc("plone27_justicia_sanciones_de", { p_bank: a.c.bank_id, p_dip: dip });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ sanciones: data ?? [] });
}
