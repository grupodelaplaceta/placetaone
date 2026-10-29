import { staffFrom } from "@/lib/supabase";
import { ENDPOINTS } from "@/lib/scopes";
import { envAny, SUPABASE_URL_NAMES, SUPABASE_ANON_NAMES, SUPABASE_SERVICE_NAMES } from "@/lib/env";
export const dynamic = "force-dynamic";
type Chk = { name: string; ok: boolean; detail: string; ms?: number };
// Estado del sistema: APIs (responden y exigen credenciales), base de datos, configuración, seguridad e integridad de datos.
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "financiero", "aprobador"]); if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const origin = new URL(req.url).origin; const t0 = Date.now();
  const db = await s.db.from("plone27_banks").select("id", { count: "exact", head: true });
  const probes: [string, string, number][] = [...ENDPOINTS.map(([m, p]) => [m, p.replace("{iban}", "PZ-0000-0000").replace("{ref}", "x"), 401] as [string, string, number]),
    ["GET", "/api/public-config", 200], ["GET", "/api/admin/overview", 403], ["GET", "/api/admin/settings", 403], ["GET", "/api/admin/r/banks", 403], ["GET", "/api/cron/webhooks", 401], ["GET", "/api/cron/alerts", 401]];
  const apis: Chk[] = await Promise.all(probes.map(async ([m, p, want]) => { const t = Date.now();
    try { const r = await fetch(origin + p, { method: m, signal: AbortSignal.timeout(6000), headers: { "content-type": "application/json" }, body: m === "POST" ? "{}" : undefined });
      return { name: `${m} ${p}`, ok: r.status === want, ms: Date.now() - t, detail: r.status === want ? (want === 200 ? "responde" : "responde y exige credenciales") : `esperado ${want}, recibido ${r.status}` };
    } catch (e) { return { name: `${m} ${p}`, ok: false, ms: Date.now() - t, detail: (e as Error).message }; } }));
  const anon = envAny(SUPABASE_ANON_NAMES), svc = envAny(SUPABASE_SERVICE_NAMES);
  const config: Chk[] = [
    { name: "Base de datos", ok: !db.error, ms: Date.now() - t0, detail: db.error ? db.error.message : "conectada" },
    { name: "URL de Supabase", ok: !!envAny(SUPABASE_URL_NAMES), detail: "NEXT_PUBLIC_SUPABASE_URL" },
    { name: "Clave pública (anon)", ok: !!anon, detail: "NEXT_PUBLIC_SUPABASE_ANON_KEY" },
    { name: "Clave de servicio", ok: !!svc, detail: "SUPABASE_SERVICE_ROLE_KEY (solo servidor)" },
    { name: "Clave de servicio distinta de la pública", ok: !!svc && svc !== anon, detail: "si coinciden, la clave privilegiada estaría expuesta" },
    { name: "CRON_SECRET robusto", ok: (process.env.CRON_SECRET ?? "").length >= 24, detail: "mínimo 24 caracteres" },
    { name: "Segundo factor del personal", ok: process.env.REQUIRE_MFA === "true", detail: "REQUIRE_MFA=true (recomendado en producción)" },
    { name: "Avisos de alertas", ok: !!process.env.ALERT_WEBHOOK_URL, detail: "ALERT_WEBHOOK_URL" }];
  const [integrity, security] = await Promise.all([s.db.rpc("plone27_integrity_report"), s.db.rpc("plone27_security_report")]);
  return Response.json({ at: new Date().toISOString(), apis, config, integrity: integrity.data ?? [], security: security.data ?? [], errors: [integrity.error?.message, security.error?.message].filter(Boolean) });
}
