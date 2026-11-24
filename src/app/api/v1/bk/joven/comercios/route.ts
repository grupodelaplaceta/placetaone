import { clientFrom } from "@/lib/apikey";

// Comercios Placeta Joven de tu entidad: los únicos a los que una cuenta Joven puede pagar (joven:gestionar).
export async function GET(req: Request) {
  const a = await clientFrom(req, "joven:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_accounts").select("iban,name")
    .eq("bank_id", a.c.bank_id).eq("kind", "business").eq("comercio_joven", true).eq("status", "active").order("name");
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ comercios: data ?? [] });
}
