import { admin } from "@/lib/supabase";
// Avisa a un webhook compatible con Slack/Teams/Discord (ALERT_WEBHOOK_URL) si hay alertas abiertas.
export async function GET(req: Request) {
  if (req.headers.get("authorization") !== `Bearer ${process.env.CRON_SECRET}`) return Response.json({ error: "No autorizado" }, { status: 401 });
  const { data } = await admin().from("plone27_alerts").select("alerta,n");
  const open = (data ?? []).filter(a => a.n > 0);
  if (open.length && process.env.ALERT_WEBHOOK_URL) {
    const text = "Placeta One · alertas: " + open.map(a => `${a.alerta.replaceAll("_", " ")}=${a.n}`).join(", ");
    await fetch(process.env.ALERT_WEBHOOK_URL, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text, content: text }) });
  }
  return Response.json({ open });
}
