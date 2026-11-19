import { clientFrom } from "@/lib/apikey";
import { normalizarDip } from "@/lib/sesion";

// Búsqueda por DIP para el banco: sus cuentas (solo de su entidad). Solo servidor. Requiere el permiso personas:buscar.
export async function GET(req: Request) {
  const a = await clientFrom(req, "personas:buscar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const dip = normalizarDip(new URL(req.url).searchParams.get("dip"));
  if (!dip) return Response.json({ error: "DIP no válido" }, { status: 400 });
  const { data, error } = await a.db.rpc("plone27_bk_buscar_dip", { p_client: a.c.id, p_dip: dip });
  if (error) return Response.json({ error: "No se puede buscar" }, { status: 422 });
  return Response.json({ cuentas: Array.isArray(data) ? data : [] });
}
