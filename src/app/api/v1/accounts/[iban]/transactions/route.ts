import { clientFrom, ownAccount } from "@/lib/apikey";
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "transactions:read"); if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const id = await ownAccount(a.db, a.c.bank_id, (await params).iban); if (!id) return Response.json({ error: "No encontrada" }, { status: 404 });
  const { data } = await a.db.from("plone27_ledger_entries").select("direction,amount,created_at,tx:plone27_transactions(ref,transfer_ref,kind,memo,status)").eq("account_id", id).order("id", { ascending: false }).limit(50);
  return Response.json(data);
}
