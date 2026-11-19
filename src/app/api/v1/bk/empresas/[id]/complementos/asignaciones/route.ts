import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa, personaPorDip } from "@/lib/empresas";

// Asignar un complemento de actividad a un contrato (retribuciones:gestionar).
// Body: { retribucion, complemento, importe?, desde?, hasta?, motivo, dip_actor }
// Si no indicas importe, se usa el importe base del complemento. Desde, por defecto hoy.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "retribuciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { data, error } = await a.db.rpc("plone27_bk_complemento_asignar", { p_bank: a.c.bank_id, p_cip: c.cip, p_actor: actor,
      p_retribucion: String(b?.retribucion ?? ""), p_complemento: String(b?.complemento ?? ""),
      p_importe: b?.importe == null ? null : Number(b.importe), p_desde: b?.desde ? String(b.desde) : null,
      p_hasta: b?.hasta ? String(b.hasta) : null, p_motivo: String(b?.motivo ?? "") });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ asignacion: data }, { status: 201 });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
