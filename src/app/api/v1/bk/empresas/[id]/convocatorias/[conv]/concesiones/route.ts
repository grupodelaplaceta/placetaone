import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa, personaPorDip } from "@/lib/empresas";

// Conceder dentro de una convocatoria de la empresa (subvenciones:gestionar). Reserva el importe.
// Body: { beneficiary, amount, caduca?, dip_actor }. Bloquea la autoconcesión y respeta el destino.
export async function POST(req: Request, { params }: { params: Promise<{ id: string; conv: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id, conv } = await params;
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { data, error } = await a.db.rpc("plone27_convocatoria_conceder", {
      p_bank: a.c.bank_id, p_cip: c.cip, p_conv: conv, p_beneficiary: String(b?.beneficiary ?? ""),
      p_amount: Number(b?.amount), p_caduca: b?.caduca ? String(b.caduca) : null, p_actor: actor,
    });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ subvencion: data }, { status: 201 });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
