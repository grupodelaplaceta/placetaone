import { clientFrom, hexAleatorio } from "@/lib/apikey";
// Aprobar y pagar una justificación (subvenciones:gestionar). Cabecera Idempotency-Key obligatoria.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const clave = req.headers.get("idempotency-key") ?? hexAleatorio(12);
  if (!/^[A-Za-z0-9_-]{8,80}$/.test(clave)) return Response.json({ error: "Idempotency-Key no válida (8 a 80 caracteres)" }, { status: 400 });
  const { data, error } = await a.db.rpc("plone27_bk_justificacion_pagar", { p_bank: a.c.bank_id, p_just: id, p_key: `bk-reimb:${a.c.bank_id}:${clave}`, p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ transaccion: data });
}
