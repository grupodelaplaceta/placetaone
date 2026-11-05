import { clientFrom } from "@/lib/apikey";
// Concesiones de un programa (subvenciones:gestionar)
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { data, error } = await a.db.rpc("plone27_bk_concesiones", { p_bank: a.c.bank_id, p_program: id });
  if (error) return Response.json({ error: "No se pueden listar las concesiones" }, { status: 422 });
  return Response.json({ concesiones: data ?? [] });
}
// Body: { beneficiario: "PZ-…", concedido }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_bk_concesion_crear", { p_bank: a.c.bank_id, p_program: id,
    p_beneficiary_iban: String(b?.beneficiario ?? ""), p_granted: Number(b?.concedido), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ concesion: data }, { status: 201 });
}
