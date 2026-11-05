import { clientFrom } from "@/lib/apikey";
import { subirLogo } from "@/lib/logos";

// Subir el logo de la entidad (branding:gestionar). Body: { imagen: "<base64 o data URI>" } (PNG, JPG o WEBP, máx. 512 KB).
export async function POST(req: Request) {
  const a = await clientFrom(req, "branding:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const r = await subirLogo(`banco/${a.c.bank_id}`, String(b?.imagen ?? ""));
  if ("error" in r) return Response.json({ error: r.error }, { status: 422 });
  const actual = await a.db.from("plone27_banks").select("color_principal,nombre_visible,texto_pie").eq("id", a.c.bank_id).maybeSingle();
  const { error } = await a.db.rpc("plone27_bk_branding_set", { p_bank: a.c.bank_id, p_logo: r.url, p_color: actual.data?.color_principal ?? null,
    p_nombre: actual.data?.nombre_visible ?? null, p_texto: actual.data?.texto_pie ?? null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ logo_url: r.url }, { status: 201 });
}
