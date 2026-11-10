import { clientFrom } from "@/lib/apikey";

// Añadir una cuenta a la empresa (empresas:gestionar). Da permisos a sus titulares y asegura su entidad institucional.
// Body: { iban, dip_actor? }. dip_actor es opcional: la clave de la entidad ya identifica al banco; si se indica, debe ser titular.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  let actor: string | null = null;
  if (b?.dip_actor) {
    const r = await a.db.rpc("plone27_persona", { p_dip: String(b.dip_actor) });
    if (r.error) return Response.json({ error: r.error.message }, { status: 422 });
    actor = r.data as string;
  }
  const { data, error } = await a.db.rpc("plone27_empresa_cuenta_anadir", { p_bank: a.c.bank_id, p_empresa: id, p_iban: String(b?.iban ?? ""), p_actor: actor });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ anadida: true, cip: data }, { status: 201 });
}
