import { clientFrom, ownAccount } from "@/lib/apikey";
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "cards:read"); if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const id = await ownAccount(a.db, a.c.bank_id, (await params).iban); if (!id) return Response.json({ error: "No encontrada" }, { status: 404 });
  const { data } = await a.db.from("plone27_cards").select("card_ref,kind,status,last4,expires,is_test").eq("account_id", id);
  return Response.json(data);
}
