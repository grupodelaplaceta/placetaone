import { clientFrom } from "@/lib/apikey";
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "accounts:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { iban } = await params;
  const { data: acc } = await a.db.from("plone27_account_balances").select("account_id,name,status,booked,reserved").eq("account_id",
    (await a.db.from("plone27_accounts").select("id,bank_id").eq("iban", iban).maybeSingle()).data?.id ?? "");
  const { data: meta } = await a.db.from("plone27_accounts").select("bank_id,status").eq("iban", iban).maybeSingle();
  if (!meta || !acc?.[0]) return Response.json({ error: "No encontrada" }, { status: 404 });
  if (meta.bank_id !== a.c.bank_id) return Response.json({ iban, status: meta.status }); // otra entidad: solo existencia/estado
  const x = acc[0]; return Response.json({ iban, name: x.name, status: x.status, booked: x.booked, reserved: x.reserved, available: x.booked - x.reserved });
}
