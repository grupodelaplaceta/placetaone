import { staffFrom } from "@/lib/supabase";
// Estadísticas y análisis. Solo lectura. Vistas permitidas: métricas diarias y vistas planas del libro.
const VISTAS: Record<string, { fecha: string; limite: number }> = {
  metricas: { fecha: "fecha", limite: 20000 },
  plone27_v_movimientos: { fecha: "created_at", limite: 5000 },
  plone27_v_declaraciones: { fecha: "periodo", limite: 5000 },
  plone27_v_recibos: { fecha: "created_at", limite: 5000 },
};
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "financiero", "fiscal", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const u = new URL(req.url);
  const vista = u.searchParams.get("vista") ?? "metricas";
  const cfg = VISTAS[vista];
  if (!cfg) return Response.json({ error: "Vista no permitida", permitidas: Object.keys(VISTAS) }, { status: 400 });
  const hoy = new Date().toISOString().slice(0, 10);
  const desde = u.searchParams.get("desde") ?? new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
  const hasta = u.searchParams.get("hasta") ?? hoy;
  const limite = Math.min(Number(u.searchParams.get("limite") ?? cfg.limite), cfg.limite);
  let q = s.db.from(vista).select("*").gte(cfg.fecha, desde).lte(cfg.fecha, hasta).limit(limite);
  const area = u.searchParams.get("area"); if (vista === "metricas" && area) q = q.eq("area", area);
  const { data, error } = await q;
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json({ vista, desde, hasta, filas: data?.length ?? 0, datos: data ?? [] });
}
