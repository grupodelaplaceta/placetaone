import { clientFrom } from "@/lib/apikey";
import { personaPorDip } from "@/lib/empresas";

// La entidad decide si lo recuperado de una deuda se vuelve a autorizar en su convocatoria (subvenciones:gestionar).
// Body: { reautoriza_recuperados: boolean, dip_actor }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const cv = await a.db.from("plone27_convocatorias").select("entidad").eq("id", id).maybeSingle();
  if (!cv.data) return Response.json({ error: "Convocatoria no encontrada" }, { status: 404 });
  const ent = await a.db.from("plone27_accounts").select("bank_id").eq("id", cv.data.entidad as string).maybeSingle();
  if (ent.data?.bank_id !== a.c.bank_id) return Response.json({ error: "Convocatoria no encontrada en tu entidad" }, { status: 404 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  if (typeof b?.reautoriza_recuperados !== "boolean") return Response.json({ error: "reautoriza_recuperados debe ser true o false" }, { status: 400 });
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { error } = await a.db.rpc("plone27_convocatoria_reautorizacion_fijar", { p_conv: id, p_valor: b.reautoriza_recuperados, p_actor: actor });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ ok: true });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
