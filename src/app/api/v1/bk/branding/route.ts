import { clientFrom } from "@/lib/apikey";

// Identidad visual de la entidad en la ventana de pago (branding:gestionar). Formatos: logo https, color #RRGGBB.
export async function GET(req: Request) {
  const a = await clientFrom(req, "branding:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_banks").select("nombre_visible,logo_url,color_principal,texto_pie").eq("id", a.c.bank_id).maybeSingle();
  if (error) return Response.json({ error: "No se puede consultar" }, { status: 422 });
  return Response.json(data ?? {});
}

// Body: { nombre_visible?, logo_url?, color_principal?, texto_pie? }. Campos vacíos quitan el valor.
export async function PUT(req: Request) {
  const a = await clientFrom(req, "branding:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const v = (x: unknown) => (x === undefined || x === null || String(x).trim() === "" ? null : String(x).trim());
  const { error } = await a.db.rpc("plone27_bk_branding_set", { p_bank: a.c.bank_id, p_logo: v(b?.logo_url), p_color: v(b?.color_principal),
    p_nombre: v(b?.nombre_visible), p_texto: v(b?.texto_pie) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ actualizado: true });
}
