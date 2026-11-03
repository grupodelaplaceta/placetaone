import { clientFrom } from "@/lib/apikey";

// El banco pagador canjea el código de pago que le ha dado su cliente (pagos:resolver).
// Body: { codigo: "PAG-XXXX-XXXX-XXXX-XXXX", dip: DIP del cliente }. Devuelve el detalle del pago para que el cliente lo apruebe.
export async function POST(req: Request) {
  const a = await clientFrom(req, "pagos:resolver");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_checkout_por_codigo", { p_bank: a.c.bank_id, p_codigo: String(b?.codigo ?? ""), p_dip: String(b?.dip ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}
