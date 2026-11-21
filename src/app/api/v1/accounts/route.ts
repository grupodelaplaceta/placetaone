import { clientFrom } from "@/lib/apikey";
// Abre una cuenta a partir de un producto activo de la propia entidad. El IBAN lo genera el servidor.
export async function POST(req: Request) {
  const a = await clientFrom(req, "accounts:write"); if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null); if (!b?.product_id || !b?.name) return Response.json({ error: "product_id y name requeridos" }, { status: 400 });
  const { data: p } = await a.db.from("plone27_products").select("bank_id").eq("id", b.product_id).maybeSingle();
  if (!p || p.bank_id !== a.c.bank_id) return Response.json({ error: "Producto no pertenece a su entidad" }, { status: 403 });
  const { data, error } = await a.db.rpc("plone27_open_account_p", { p_product: b.product_id, p_name: b.name, p_owner: b.owner ?? null, p_actor: a.c.id });
  return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ iban: data.iban });
}
