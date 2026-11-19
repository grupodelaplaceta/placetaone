import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Marcar como leídas. Body: { ids?: number[] }. Sin ids, marca todas las no leídas.
export async function POST(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const b = await req.json().catch(() => ({}));
  const ids = Array.isArray(b?.ids) ? b.ids.map(Number).filter((n: number) => Number.isInteger(n)) : null;
  const { data, error } = await s.db.rpc("plone27_user_notifications_read", { p_user: s.usuario, p_bank: s.banco, p_ids: ids });
  if (error) return respuesta(req, { error: "No se pueden marcar" }, 422, s.cliente);
  return respuesta(req, { marcadas: data ?? 0 }, 200, s.cliente);
}
