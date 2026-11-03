import { staffFrom } from "@/lib/supabase";
export async function POST(req: Request) {
  const s = await staffFrom(req, ["financiero", "gestor_bancario"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const key = req.headers.get("idempotency-key");
  if (!key) return Response.json({ error: "Falta Idempotency-Key" }, { status: 400 });
  const b = await req.json().catch(() => null);
  const amount = Number(b?.amount);
  if (!b?.from || !b?.to || !(amount > 0) || Math.round(amount * 100) !== amount * 100)
    return Response.json({ error: "Datos inválidos (importe en Pz, máx. 2 decimales)" }, { status: 400 });
  const { data, error } = await s.db.rpc("plone27_transfer_fee", {
    p_key: key, p_from: b.from, p_to: b.to, p_amount: amount, p_memo: b.memo ?? null, p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ transaction_id: data });
}
