import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Aplicar a una tarjeta propia un diseño comprado por la cuenta de esa tarjeta.
// Body: { codigo: "DIS-00001" }  o  { codigo: null } para quitar el diseño.
export async function POST(req: Request, { params }: { params: Promise<{ ref: string }> }) {
  const r = await sesionDe(req, "me:seguridad");
  if ("err" in r) return r.err;
  const { s } = r;
  const { ref } = await params;
  const b = await req.json().catch(() => null);
  const codigo = b?.codigo === null || b?.codigo === undefined ? null : String(b.codigo);
  const { data, error } = await s.db.rpc("plone27_user_card_design", { p_user: s.usuario, p_bank: s.banco, p_ref: ref, p_codigo: codigo });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, data, 200, s.cliente);
}
