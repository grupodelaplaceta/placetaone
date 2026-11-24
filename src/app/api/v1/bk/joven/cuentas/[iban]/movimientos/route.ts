import { clientFrom } from "@/lib/apikey";

// Movimientos de una cuenta Placeta Joven (joven:leer, solo lectura, de cualquier banco con el permiso). Query: desde, hasta (AAAA-MM-DD), limite (máx. 200).
// Por defecto, los últimos 30 días.
export async function GET(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "joven:leer");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { iban } = await params;
  const u = new URL(req.url);
  const hoy = new Date().toISOString().slice(0, 10);
  const hace30 = new Date(Date.now() - 30 * 864e5).toISOString().slice(0, 10);
  const desde = u.searchParams.get("desde") ?? hace30;
  const hasta = u.searchParams.get("hasta") ?? hoy;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(desde) || !/^\d{4}-\d{2}-\d{2}$/.test(hasta)) return Response.json({ error: "desde y hasta deben ser AAAA-MM-DD" }, { status: 400 });
  if (desde > hasta) return Response.json({ error: "desde no puede ser posterior a hasta" }, { status: 400 });
  const limite = Number(u.searchParams.get("limite") ?? 50);
  const { data, error } = await a.db.rpc("plone27_joven_movimientos", { p_bank: null, p_iban: iban, p_desde: desde, p_hasta: hasta, p_limite: limite });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ movimientos: data ?? [] });
}
