import { clientFrom } from "@/lib/apikey";
// Justificaciones de gasto de los beneficiarios (subvenciones:gestionar). Query: concesion?
export async function GET(req: Request) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const grant = new URL(req.url).searchParams.get("concesion");
  const { data, error } = await a.db.rpc("plone27_bk_justificaciones", { p_bank: a.c.bank_id, p_grant: grant });
  if (error) return Response.json({ error: "No se pueden listar las justificaciones" }, { status: 422 });
  return Response.json({ justificaciones: data ?? [] });
}
// Body: { concesion, transaccion, factura, importe }. Las reglas del programa se comprueban aquí.
export async function POST(req: Request) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_bk_justificar", { p_bank: a.c.bank_id, p_grant: String(b?.concesion ?? ""),
    p_tx: String(b?.transaccion ?? ""), p_invoice: String(b?.factura ?? ""), p_amount: Number(b?.importe), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ justificacion: data }, { status: 201 });
}
