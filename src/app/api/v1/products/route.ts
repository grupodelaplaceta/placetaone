import { clientFrom } from "@/lib/apikey";
export async function GET(req: Request) {
  const a = await clientFrom(req, "products:read"); if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data } = await a.db.from("plone27_products").select("id,code,kind,name,description,daily_limit,credit_limit,monthly_fee,interest_rate,min_age,requires_guardian,valid_from,valid_to").eq("bank_id", a.c.bank_id).eq("status", "active");
  return Response.json(data);
}
