import { admin } from "@/lib/supabase";

// Confirmar el pago con el código de 6 dígitos. Tres intentos. Body: { codigo }
const NO_STORE = { "cache-control": "no-store" };
export async function POST(req: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!/^[0-9a-f]{64}$/.test(token)) return Response.json({ ok: false, error: "No encontrado" }, { status: 404, headers: NO_STORE });
  const b = await req.json().catch(() => null);
  const codigo = String(b?.codigo ?? "");
  if (!/^\d{6}$/.test(codigo)) return Response.json({ ok: false, error: "El código tiene 6 dígitos" }, { status: 400, headers: NO_STORE });
  const { data, error } = await admin().rpc("plone27_checkout_confirm", { p_token: token, p_codigo: codigo });
  if (error) return Response.json({ ok: false, error: "No se puede confirmar ahora" }, { status: 422, headers: NO_STORE });
  return Response.json(data, { status: data?.ok ? 200 : 422, headers: NO_STORE });
}
