import { clientFrom } from "@/lib/apikey";

// Expediente de una persona en la entidad (retribuciones:gestionar). Query: cip, dip.
export async function GET(req: Request) {
  const a = await clientFrom(req, "retribuciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const u = new URL(req.url);
  const persona = await a.db.rpc("plone27_persona", { p_dip: u.searchParams.get("dip") ?? "" });
  if (persona.error) return Response.json({ error: persona.error.message }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_expediente", { p_bank: a.c.bank_id, p_cip: u.searchParams.get("cip") ?? "", p_persona: persona.data });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  if (!data) return Response.json({ error: "Entidad no encontrada" }, { status: 404 });
  return Response.json(data);
}
