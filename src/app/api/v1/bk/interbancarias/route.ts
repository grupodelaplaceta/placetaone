import { clientFrom } from "@/lib/apikey";

// Operaciones interbancarias de la entidad: pagadas por sus clientes y cobradas en sus comercios (interbancarias:gestionar).
// Query: desde, hasta (AAAA-MM-DD). Por defecto, los últimos 30 días.
export async function GET(req: Request) {
  const a = await clientFrom(req, "interbancarias:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const u = new URL(req.url);
  const hoy = new Date();
  const hace30 = new Date(hoy.getTime() - 30 * 864e5);
  const desde = u.searchParams.get("desde") ?? hace30.toISOString().slice(0, 10);
  const hasta = u.searchParams.get("hasta") ?? hoy.toISOString().slice(0, 10);
  const { data, error } = await a.db.rpc("plone27_interbancarias", { p_bank: a.c.bank_id, p_desde: desde, p_hasta: hasta });
  if (error) return Response.json({ error: "No se pueden listar las operaciones" }, { status: 422 });
  return Response.json({ operaciones: data ?? [] });
}
