import { admin } from "@/lib/supabase";

// Estado público del pago para la ventana de pago. Sin datos internos ni código.
const NO_STORE = { "cache-control": "no-store" };
export async function GET(_req: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!/^[0-9a-f]{64}$/.test(token)) return Response.json({ error: "No encontrado" }, { status: 404, headers: NO_STORE });
  const { data, error } = await admin().rpc("plone27_checkout_status", { p_token: token });
  if (error) return Response.json({ error: "No disponible" }, { status: 422, headers: NO_STORE });
  if (!data) return Response.json({ error: "No encontrado" }, { status: 404, headers: NO_STORE });
  return Response.json(data, { headers: NO_STORE });
}
