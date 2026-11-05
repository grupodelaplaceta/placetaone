// Liquidación diaria (Vercel Cron, con el secreto CRON_SECRET). No hace nada si la liquidación está desactivada.
import { admin } from "@/lib/supabase";

export async function GET(req: Request) {
  if (req.headers.get("authorization") !== `Bearer ${process.env.CRON_SECRET}`) {
    return Response.json({ error: "No autorizado" }, { status: 401 });
  }
  const hoy = new Date().toISOString().slice(0, 10);
  const { data, error } = await admin().rpc("plone27_liquidar", { p_fecha: hoy, p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ ok: true, resultado: data });
}
