import { clientFrom } from "@/lib/apikey";
// Programas de subvención o bono de la entidad (subvenciones:gestionar)
export async function GET(req: Request) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_programas", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden listar los programas" }, { status: 422 });
  return Response.json({ programas: data ?? [] });
}
// Body: { nombre, tipo: "subvencion" | "bono", presupuesto, cuenta_fondos: "PZ-…" }
export async function POST(req: Request) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_bk_programa_crear", { p_bank: a.c.bank_id, p_name: String(b?.nombre ?? ""),
    p_kind: String(b?.tipo ?? ""), p_budget: Number(b?.presupuesto), p_funding_iban: String(b?.cuenta_fondos ?? ""), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ programa: data }, { status: 201 });
}
