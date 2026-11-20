import { clientFrom } from "@/lib/apikey";
import { personaPorDip } from "@/lib/empresas";
import { programaDeBanco } from "@/lib/subvenciones";

// Crear una subvención o bono de un programa de la entidad (subvenciones:gestionar).
// Body: { program, beneficiary, amount, convocatoria?, caduca?, dip_actor }
export async function POST(req: Request) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const programa = String(b?.program ?? "");
  if (!(await programaDeBanco(a.db, a.c.bank_id, programa))) return Response.json({ error: "Programa no encontrado en tu entidad" }, { status: 404 });
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { data, error } = await a.db.rpc("plone27_grant_crear", {
      p_program: programa, p_beneficiary: String(b?.beneficiary ?? ""), p_amount: Number(b?.amount),
      p_convocatoria: b?.convocatoria ? String(b.convocatoria) : null, p_caduca: b?.caduca ? String(b.caduca) : null, p_actor: actor,
    });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ subvencion: data }, { status: 201 });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
