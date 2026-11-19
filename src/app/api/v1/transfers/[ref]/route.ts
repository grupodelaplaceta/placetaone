import { clientFrom } from "@/lib/apikey";
export async function GET(req: Request, { params }: { params: Promise<{ ref: string }> }) {
  const a = await clientFrom(req, "transfers:read"); if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data: t } = await a.db.from("plone27_transactions").select("id,ref,transfer_ref,kind,status,memo,created_at").eq("transfer_ref", (await params).ref).maybeSingle();
  if (!t) return Response.json({ error: "No encontrada" }, { status: 404 });
  const { data: e } = await a.db.from("plone27_ledger_entries").select("direction,amount,account:plone27_accounts(iban,bank_id)").eq("transaction_id", t.id);
  const mine = (e ?? []).filter((x: { account: unknown }) => (x.account as { bank_id: string } | null)?.bank_id === a.c.bank_id);
  if (!mine.length) return Response.json({ error: "No encontrada" }, { status: 404 });  // solo transferencias en las que participa su entidad
  return Response.json({ ...t, lines: mine.map((x: { direction: string; amount: number; account: unknown }) => ({ direction: x.direction, amount: x.amount, iban: (x.account as { iban: string }).iban })) });
}
