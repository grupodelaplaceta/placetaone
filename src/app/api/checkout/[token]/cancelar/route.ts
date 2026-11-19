import { admin } from "@/lib/supabase";

// Cancelar un pago pendiente (lo hace el usuario desde la ventana)
const NO_STORE = { "cache-control": "no-store" };
export async function POST(_req: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!/^[0-9a-f]{64}$/.test(token)) return Response.json({ error: "No encontrado" }, { status: 404, headers: NO_STORE });
  const { data, error } = await admin().rpc("plone27_checkout_cancel", { p_token: token });
  if (error) return Response.json({ error: "No se puede cancelar" }, { status: 422, headers: NO_STORE });
  return Response.json({ cancelado: data === true }, { headers: NO_STORE });
}
