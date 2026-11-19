import { clientFrom, ownAccount } from "@/lib/apikey";
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "receipts:read"); if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const id = await ownAccount(a.db, a.c.bank_id, (await params).iban); if (!id) return Response.json({ error: "No encontrada" }, { status: 404 });
  const { data } = await a.db.from("plone27_tax_receipts").select("ref,amount,paid_amount,status,due_date,created_at").eq("account_id", id).order("created_at", { ascending: false }).limit(50);
  return Response.json(data);
}
