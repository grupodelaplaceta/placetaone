import { clientFrom } from "@/lib/apikey";
const IBAN = /^PZ-\d{4}-\d{4}$/;
export async function POST(req: Request) {
  const a = await clientFrom(req, "transfers:write");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const key = req.headers.get("idempotency-key");
  if (!key) return Response.json({ error: "Falta Idempotency-Key" }, { status: 400 });
  const b = await req.json().catch(() => null); const amount = Number(b?.amount); const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!UUID.test(b?.user_id ?? "")) return Response.json({ error: "user_id (UUID del usuario que ordena la operación) requerido" }, { status: 400 });
  if (!IBAN.test(b?.from_iban ?? "") || !IBAN.test(b?.to_iban ?? "") || !(amount > 0) || Math.round(amount * 100) !== amount * 100)
    return Response.json({ error: "from_iban, to_iban (PZ-EEEE-CCCC) y amount en Pz (máx. 2 decimales)" }, { status: 400 });
  const { data: acc } = await a.db.from("plone27_accounts").select("id,iban,bank_id").in("iban", [b.from_iban, b.to_iban]);
  const f = acc?.find((x: { iban: string }) => x.iban === b.from_iban), t = acc?.find((x: { iban: string }) => x.iban === b.to_iban);
  if (!f || !t) return Response.json({ error: "Cuenta no encontrada" }, { status: 404 });
  if (f.bank_id !== a.c.bank_id) return Response.json({ error: "La cuenta origen no pertenece a su entidad" }, { status: 403 });
  const { data: id, error } = await a.db.rpc("plone27_transfer_user", { p_key: `${a.c.id}:${key}`, p_user: b.user_id, p_from: f.id, p_to: t.id, p_amount: amount, p_memo: b.memo ?? null, p_actor: a.c.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  const { data: tx } = await a.db.from("plone27_transactions").select("ref,transfer_ref").eq("id", id).single();
  return Response.json({ transfer: tx?.transfer_ref, operation: tx?.ref });
}
