import { clientFrom, hexAleatorio } from "@/lib/apikey";

// Webhooks de la entidad (webhooks:gestionar). El secreto se devuelve una sola vez, al crear el webhook.
export async function GET(req: Request) {
  const a = await clientFrom(req, "webhooks:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_webhooks").select("id,url,events,active").eq("bank_id", a.c.bank_id);
  if (error) return Response.json({ error: "No se puede consultar" }, { status: 422 });
  return Response.json({ webhooks: data ?? [] });
}

// Body: { url: "https://…", eventos: ["checkout.pagado", …] o ["*"] }
export async function POST(req: Request) {
  const a = await clientFrom(req, "webhooks:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const secreto = hexAleatorio(24);
  const eventos = Array.isArray(b?.eventos) ? b.eventos.map(String) : [];
  const { data, error } = await a.db.rpc("plone27_bk_webhook_crear", { p_bank: a.c.bank_id, p_url: String(b?.url ?? ""), p_eventos: eventos, p_secret: secreto });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ id: data, secreto, aviso: "Guarda el secreto ahora: no se vuelve a mostrar." }, { status: 201 });
}
