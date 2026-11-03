import { clientFrom } from "@/lib/apikey";

// Planes a plazos y suscripciones de tu entidad (solo lectura). Permiso: planes:read
export async function GET(req: Request) {
  const a = await clientFrom(req, "planes:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.rpc("plone27_bk_planes", { p_bank: a.c.bank_id });
  if (error) return Response.json({ error: "No se pueden cargar los planes" }, { status: 422 });
  return Response.json({ planes: Array.isArray(data) ? data : [] });
}
