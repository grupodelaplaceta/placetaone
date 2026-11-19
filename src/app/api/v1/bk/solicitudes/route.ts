import { clientFrom } from "@/lib/apikey";

// Crear una solicitud de una unidad (solicitudes:gestionar). Solo si la entidad tiene activadas las solicitudes.
export async function POST(req: Request) {
  const a = await clientFrom(req, "solicitudes:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const actorRes = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return Response.json({ error: actorRes.error.message }, { status: 422 });
  const cip = String(b?.cip ?? "");
  const { data, error } = await a.db.rpc("plone27_solicitud_crear", { p_bank: a.c.bank_id, p_cip: cip, p_actor: actorRes.data,
    p_unidad: String(b?.unidad ?? ""), p_tipo: String(b?.tipo ?? ""), p_importe: b?.importe ? Number(b.importe) : null,
    p_referencia: b?.referencia ? String(b.referencia) : null, p_nueva_fecha: b?.nueva_fecha ? String(b.nueva_fecha) : null,
    p_justificacion: String(b?.justificacion ?? ""), p_convocatoria: b?.convocatoria ? String(b.convocatoria) : null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ solicitud: data }, { status: 201 });
}
