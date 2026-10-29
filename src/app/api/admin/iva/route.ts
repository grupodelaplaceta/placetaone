import { staffFrom } from "@/lib/supabase";
// Hallazgos de IVA e informe del periodo. Las acciones se hacen por la pasarela /api/rpc (propuesta y aprobación).
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "fiscal", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const u = new URL(req.url);
  const hoy = new Date();
  const desde = u.searchParams.get("desde") ?? new Date(hoy.getFullYear(), hoy.getMonth(), 1).toISOString().slice(0, 10);
  const hasta = u.searchParams.get("hasta") ?? hoy.toISOString().slice(0, 10);
  const [hallazgos, accs, informe] = await Promise.all([
    s.db.from("plone27_iva_findings").select("*").order("detected_at", { ascending: false }).limit(500),
    s.db.from("plone27_accounts").select("id,iban,name"),
    s.db.rpc("plone27_iva_report", { p_desde: desde, p_hasta: hasta }),
  ]);
  const nombre = new Map((accs.data ?? []).map((a: { id: string; iban: string; name: string }) => [a.id, `${a.iban} · ${a.name}`]));
  return Response.json({
    hallazgos: (hallazgos.data ?? []).map((h: Record<string, unknown>) => ({
      ...h, receptor: nombre.get(h.account_id as string) ?? "", pagador: nombre.get(h.counterpart_account as string) ?? "" })),
    informe: informe.data, desde, hasta,
  });
}
