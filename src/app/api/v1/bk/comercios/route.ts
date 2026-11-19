import { clientFrom } from "@/lib/apikey";
// Directorio de comercios (cuentas de empresa activas) con su categoría. Sin saldos (politicas:gestionar)
export async function GET(req: Request) {
  const a = await clientFrom(req, "politicas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_comercios", {});
  if (error) return Response.json({ error: "No se pueden listar los comercios" }, { status: 422 });
  return Response.json({ comercios: data ?? [] });
}
