import { staffFrom } from "@/lib/supabase";
// Resumen del panel. Siempre devuelve arrays: si una consulta falla, la sección llega vacía y se informa el error.
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "financiero", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [alerts, banks, audit] = await Promise.all([
    s.db.from("plone27_alerts").select("*"),
    s.db.from("plone27_banks").select("code,name,status").order("code"),
    s.db.from("plone27_audit_log").select("id,actor,action,entity,entity_id,at").order("id", { ascending: false }).limit(30),
  ]);
  const errores = [alerts.error?.message, banks.error?.message, audit.error?.message].filter(Boolean);
  return Response.json({
    alerts: alerts.data ?? [],
    banks: banks.data ?? [],
    audit: audit.data ?? [],
    errores,
  });
}
