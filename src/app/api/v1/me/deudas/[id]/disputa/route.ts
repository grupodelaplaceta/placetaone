import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Reclamar sobre una deuda pagada (me:disputas: permiso propio, no concedido por defecto). Body: { monto, motivo }. Plazo: 60 días desde el vencimiento.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const r = await sesionDe(req, "me:disputas");
  if ("err" in r) return r.err;
  const { s } = r;
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const { data, error } = await s.db.rpc("plone27_user_disputa_abrir", { p_user: s.usuario, p_bank: s.banco, p_debt: id, p_monto: Number(b?.monto), p_motivo: String(b?.motivo ?? "") });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { disputa: data }, 201, s.cliente);
}
