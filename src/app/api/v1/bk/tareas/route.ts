import { clientFrom } from "@/lib/apikey";

// Registrar una tarea que genera un complemento (tareas:gestionar). Pensado para apps como NEXE.
// Body: cip, dip (persona que realizó la tarea), unidad, concepto, importe, referencia_externa (única)
export async function POST(req: Request) {
  const a = await clientFrom(req, "tareas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const persona = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip ?? "") });
  if (persona.error) return Response.json({ error: persona.error.message }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_tarea_registrar", { p_bank: a.c.bank_id, p_cip: String(b?.cip ?? ""), p_persona: persona.data,
    p_unidad: String(b?.unidad ?? ""), p_concepto: String(b?.concepto ?? ""), p_importe: Number(b?.importe), p_referencia: String(b?.referencia_externa ?? ""),
    p_origen: `cliente:${a.c.id}` });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ tarea: data }, { status: 201 });
}
