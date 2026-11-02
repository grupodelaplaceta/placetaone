import { staffFrom } from "@/lib/supabase";
// Solicitudes de cuentas y préstamos pendientes de revisión, y decisión del personal.
export async function GET(req: Request) {
  const s = await staffFrom(req, []); if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  let q = s.db.from("plone27_solicitudes").select("id,persona,bank_id,tipo,importe,cuotas,motivo,product_id,estado,creada").eq("estado", "pendiente").order("creada", { ascending: true }).limit(200);
  if (s.bank) q = q.eq("bank_id", s.bank);
  const { data, error } = await q; if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ solicitudes: data ?? [] });
}
export async function POST(req: Request) {
  const s = await staffFrom(req, []); if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = (await req.json().catch(() => ({}))) as { id?: string; aprobar?: boolean; nota?: string };
  if (!b.id || typeof b.aprobar !== "boolean") return Response.json({ error: "Falta id o decisión" }, { status: 400 });
  const { error } = await s.db.rpc("plone27_solicitud_decidir", { p_id: b.id, p_actor: s.id, p_aprobar: b.aprobar, p_nota: b.nota ?? null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ ok: true });
}
