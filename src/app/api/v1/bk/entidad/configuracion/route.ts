import { clientFrom } from "@/lib/apikey";

// Activar las solicitudes de unidades y fijar la doble firma de la entidad (entidad:configurar).
export async function PUT(req: Request) {
  const a = await clientFrom(req, "entidad:configurar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actorRes = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return Response.json({ error: actorRes.error.message }, { status: 422 });
  const cip = String(b?.cip ?? "");
  const { error } = await a.db.rpc("plone27_entidad_config", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data,
    p_solicitudes: Boolean(b?.solicitudes_activas), p_doble_firma: b?.doble_firma_desde ? Number(b.doble_firma_desde) : null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ configurada: true });
}
