import { clientFrom } from "@/lib/apikey";
import { normalizarDip } from "@/lib/sesion";

// El banco da de alta a su usuario en una de SUS cuentas. Solo servidor (clave; las claves de navegador se rechazan).
export async function POST(req: Request) {
  const a = await clientFrom(req, "usuarios:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const { data: cuenta } = await a.db.from("plone27_accounts").select("id")
    .eq("iban", String(b?.iban ?? "")).eq("bank_id", a.c.bank_id).maybeSingle();
  if (!cuenta) return Response.json({ error: "Cuenta no encontrada en esta entidad" }, { status: 404 });
  const dip = normalizarDip(b?.dip);
  if (!dip) return Response.json({ error: "DIP no válido" }, { status: 400 });
  const { error } = await a.db.rpc("plone27_client_link_account", {
    p_client: a.c.id, p_dip: dip, p_account: cuenta.id, p_role: String(b?.rol ?? "holder") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ vinculado: true }, { status: 201 });
}
