import { staffFrom } from "@/lib/supabase";
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "financiero", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [alerts, banks, audit, formats] = await Promise.all([
    s.db.from("plone27_alerts").select("*"),
    s.db.from("plone27_banks").select("code,name,status").order("code"),
    s.db.from("plone27_audit_log").select("id,actor,action,entity,entity_id,at").order("id", { ascending: false }).limit(30),
    s.db.from("plone27_numbering_formats").select("kind,version,prefix,status").eq("status", "published").order("kind"),
  ]);
  return Response.json({ alerts: alerts.data, banks: banks.data, audit: audit.data, formats: formats.data });
}
