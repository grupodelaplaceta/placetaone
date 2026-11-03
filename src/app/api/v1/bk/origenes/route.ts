import { clientFrom } from "@/lib/apikey";

// Orígenes de navegador de tu cliente (CORS). Solo servidor. Un origen nuevo queda PENDIENTE hasta que Placeta lo apruebe.
const PRUEBAS_ACTIVO = () => process.env.PLACETA_ENTORNO === "pruebas";

// Lista de orígenes y su estado
export async function GET(req: Request) {
  const a = await clientFrom(req, "origenes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_client_origins_list", { p_client: a.c.id });
  if (error) return Response.json({ error: "No se pueden listar" }, { status: 422 });
  return Response.json({ origenes: Array.isArray(data) ? data : [] });
}

// Solicitar un origen. Body: { origen: "https://app.tubanco.es", entorno?: "produccion" | "pruebas" }
// "pruebas" (localhost incluido) solo se acepta en un entorno de pruebas.
export async function POST(req: Request) {
  const a = await clientFrom(req, "origenes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const entorno = b?.entorno === "pruebas" ? "pruebas" : "produccion";
  if (entorno === "pruebas" && !PRUEBAS_ACTIVO()) return Response.json({ error: "El entorno de pruebas no está disponible aquí" }, { status: 400 });
  const { data, error } = await a.db.rpc("plone27_client_origin_request", { p_client: a.c.id, p_origin: String(b?.origen ?? ""), p_entorno: entorno });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ origen: String(b?.origen ?? "").toLowerCase(), estado: data }, { status: 201 });
}

// Retirar un origen. ?origen=https://app.tubanco.es
export async function DELETE(req: Request) {
  const a = await clientFrom(req, "origenes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const origen = (new URL(req.url).searchParams.get("origen") ?? "").toLowerCase();
  const { error } = await a.db.from("plone27_client_origins").delete().eq("client_id", a.c.id).eq("origin", origen);
  if (error) return Response.json({ error: "No se puede retirar" }, { status: 422 });
  return Response.json({ retirado: true });
}
