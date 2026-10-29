import { admin } from "@/lib/supabase";
// Ejecución diaria de finanzas: RBU, programadas, cuotas de producto, interés de crédito, membresías,
// nóminas, cuotas y suscripciones, mora, recargos (si están activos), autocobro de recibos y deudas.
// Vercel Cron envía Authorization: Bearer $CRON_SECRET. Cada paso es independiente: un fallo queda como incidencia.
export async function GET(req: Request) {
  if (req.headers.get("authorization") !== `Bearer ${process.env.CRON_SECRET}`) return Response.json({ error: "No autorizado" }, { status: 401 });
  const { data, error } = await admin().rpc("plone27_finanzas_daily", { p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json(data);
}
