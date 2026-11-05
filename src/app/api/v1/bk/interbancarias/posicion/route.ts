import { clientFrom } from "@/lib/apikey";

// Posición neta de la entidad frente a cada banco (interbancarias:gestionar). neto > 0: otros bancos le deben.
// Query: desde, hasta (AAAA-MM-DD). Por defecto, los últimos 30 días.
export async function GET(req: Request) {
  const a = await clientFrom(req, "interbancarias:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const u = new URL(req.url);
  const hoy = new Date();
  const hace30 = new Date(hoy.getTime() - 30 * 864e5);
  const desde = u.searchParams.get("desde") ?? hace30.toISOString().slice(0, 10);
  const hasta = u.searchParams.get("hasta") ?? hoy.toISOString().slice(0, 10);
  const { data, error } = await a.db.rpc("plone27_posicion_interbancaria", { p_bank: a.c.bank_id, p_desde: desde, p_hasta: hasta });
  if (error) return Response.json({ error: "No se puede calcular la posición" }, { status: 422 });
  return Response.json({ posicion: data ?? [] });
}
