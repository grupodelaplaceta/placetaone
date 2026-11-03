import { clientFrom } from "@/lib/apikey";

// Identidad del comercio (este cliente de API) en la ventana de pago (branding:gestionar).
// Body: { nombre_comercial?, logo_url?, color_principal? }
export async function PUT(req: Request) {
  const a = await clientFrom(req, "branding:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const v = (x: unknown) => (x === undefined || x === null || String(x).trim() === "" ? null : String(x).trim());
  const { error } = await a.db.rpc("plone27_bk_branding_comercio_set", { p_client: a.c.id, p_bank: a.c.bank_id,
    p_logo: v(b?.logo_url), p_color: v(b?.color_principal), p_nombre: v(b?.nombre_comercial) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ actualizado: true });
}
