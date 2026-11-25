import { admin } from "@/lib/supabase";
// Ejecución diaria de finanzas: RBU, programadas, cuotas de producto, interés de crédito, membresías,
// nóminas, cuotas y suscripciones, mora, recargos (si están activos), autocobro de recibos y deudas.
// Vercel Cron envía Authorization: Bearer $CRON_SECRET. Cada paso es independiente: un fallo queda como incidencia.
export async function GET(req: Request) {
  if (req.headers.get("authorization") !== `Bearer ${process.env.CRON_SECRET}`) return Response.json({ error: "No autorizado" }, { status: 401 });
  const { data, error } = await admin().rpc("plone27_finanzas_daily", { p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 500 });
  await admin().rpc("plone27_grants_caducar", { p_actor: null });
  await admin().rpc("plone27_joven_caducar_elegibilidad", { p_actor: null });
  await admin().rpc("plone27_sancion_firme_auto", { p_actor: null });   // sanciones notificadas sin recurso dentro de plazo pasan a firmes   // Placeta Joven: congela las cuentas que ya no son elegibles   // subvenciones vencidas: liberan su autorización
  await admin().rpc("plone27_limpiar_api");   // nonces y sesiones caducadas
  return Response.json(data);
}
