import { staffFrom } from "@/lib/supabase";
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "financiero", "fiscal", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [settings, pending, banks] = await Promise.all([
    s.db.from("plone27_settings").select("*").order("category").order("key"),
    s.db.from("plone27_setting_changes").select("*").eq("status", "pending").order("at"),
    s.db.from("plone27_banks").select("id,code,name").order("code")]);
  return Response.json({ settings: settings.data, pending: pending.data, banks: banks.data });
}
