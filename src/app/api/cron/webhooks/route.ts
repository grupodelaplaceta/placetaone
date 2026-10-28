import { createHmac } from "crypto";
import { admin } from "@/lib/supabase";
// Vercel Cron envía Authorization: Bearer $CRON_SECRET
export async function GET(req: Request) {
  if (req.headers.get("authorization") !== `Bearer ${process.env.CRON_SECRET}`) return Response.json({ error: "No autorizado" }, { status: 401 });
  const db = admin();
  const { data: events } = await db.from("plone27_outbox").select("*").eq("status", "pending").order("id").limit(50);
  const { data: hooks } = await db.from("plone27_webhooks").select("*").eq("active", true);
  let sent = 0, failed = 0;
  for (const e of events ?? []) {
    const targets = (hooks ?? []).filter(h => e.bank_ids.includes(h.bank_id) && (h.events.includes("*") || h.events.includes(e.event)));
    let ok = true;
    for (const h of targets) {
      const body = JSON.stringify({ id: e.id, event: e.event, data: e.payload });
      try {
        const r = await fetch(h.url, { method: "POST", signal: AbortSignal.timeout(8000),
          headers: { "content-type": "application/json", "x-placeta-signature": createHmac("sha256", h.secret).update(body).digest("hex") }, body });
        ok = ok && r.ok;
      } catch { ok = false; }
    }
    const attempts = e.attempts + 1;
    await db.from("plone27_outbox").update({ attempts, status: ok ? "sent" : attempts >= 5 ? "failed" : "pending" }).eq("id", e.id);
    ok ? sent++ : failed++;
  }
  return Response.json({ sent, failed });
}
