import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Suspender ('suspended') o reactivar ('active') una tarjeta propia. Body: estado.
export async function POST(req: Request, { params }: { params: Promise<{ ref: string }> }) {
  const r = await sesionDe(req, "me:seguridad");
  if ("err" in r) return r.err;
  const { s } = r;
  const { ref } = await params;
  const b = await req.json().catch(() => null);
  const { data, error } = await s.db.rpc("plone27_user_card_state", { p_user: s.usuario, p_bank: s.banco, p_ref: ref, p_estado: String(b?.estado ?? "") });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { estado: data }, 200, s.cliente);
}
