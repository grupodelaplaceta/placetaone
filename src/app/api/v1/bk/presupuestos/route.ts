import { clientFrom } from "@/lib/apikey";

// GET: informe de una unidad (presupuestos:leer). Query: cip, unidad, ejercicio.
export async function GET(req: Request) {
  const a = await clientFrom(req, "presupuestos:leer");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const u = new URL(req.url);
  const { data, error } = await a.db.rpc("plone27_informe_unidad", { p_bank: a.c.bank_id, p_cip: u.searchParams.get("cip") ?? "",
    p_unidad: u.searchParams.get("unidad") ?? "", p_ejercicio: Number(u.searchParams.get("ejercicio") ?? new Date().getFullYear()) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}

// PUT: fija el presupuesto anual de una unidad, o el general de la entidad si no se indica unidad (presupuestos:gestionar).
export async function PUT(req: Request) {
  const a = await clientFrom(req, "presupuestos:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const cip = String(b?.cip ?? "");
  const importe = Number(b?.importe);
  const res = b?.unidad
    ? await a.db.rpc("plone27_presupuesto_fijar", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actor.data, p_unidad: String(b.unidad), p_ejercicio: Number(b?.ejercicio), p_importe: importe })
    : await a.db.rpc("plone27_entidad_presupuesto_fijar", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actor.data, p_importe: importe });
  if (res.error) return Response.json({ error: res.error.message }, { status: 422 });
  return Response.json({ presupuesto: res.data });
}
