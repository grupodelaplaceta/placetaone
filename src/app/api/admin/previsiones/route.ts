import { staffFrom } from "@/lib/supabase";
// Previsión de movimientos programados y indicadores. Solo lectura.
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "financiero", "fiscal", "aprobador", "gestor_bancario"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const u = new URL(req.url);
  const hoy = new Date();
  const desde = u.searchParams.get("desde") ?? hoy.toISOString().slice(0, 10);
  const hasta = u.searchParams.get("hasta") ?? new Date(hoy.getTime() + 60 * 864e5).toISOString().slice(0, 10);
  const [prev, kpis] = await Promise.all([
    s.db.rpc("plone27_previsiones", { p_desde: desde, p_hasta: hasta }),
    s.db.rpc("plone27_kpis"),
  ]);
  if (prev.error) return Response.json({ error: prev.error.message }, { status: 500 });
  return Response.json({ desde, hasta, previsiones: prev.data ?? [], kpis: kpis.data ?? {} });
}
