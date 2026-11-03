import { clientFrom } from "@/lib/apikey";

// Crear un fondo restringido a una finalidad (presupuestos:gestionar).
export async function POST(req: Request) {
  const a = await clientFrom(req, "presupuestos:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actorRes = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return Response.json({ error: actorRes.error.message }, { status: 422 });
  const cip = String(b?.cip ?? "");
  const { data, error } = await a.db.rpc("plone27_fondo_crear", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data,
    p_unidad: String(b?.unidad ?? ""), p_nombre: String(b?.nombre ?? ""), p_finalidad: String(b?.finalidad ?? ""), p_importe: Number(b?.importe) });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ fondo: data }, { status: 201 });
}
