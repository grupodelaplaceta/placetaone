import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa, personaPorDip } from "@/lib/empresas";

// Listar las convocatorias de una empresa (subvenciones:gestionar).
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  const ent = await a.db.from("plone27_entidades").select("account_id").eq("cip", c.cip).maybeSingle();
  if (!ent.data) return Response.json({ convocatorias: [] });
  const { data, error } = await a.db.from("plone27_convocatorias")
    .select("id,nombre,tipo,importe,desde,hasta,caduca,estado,dirigida_a,empresa_destino,cuenta_fondos,reautoriza_recuperados")
    .eq("entidad", ent.data.account_id as string).order("desde");
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ convocatorias: data ?? [] });
}

// Abrir una convocatoria de subvención o bono (subvenciones:gestionar).
// Body: { nombre, tipo: "subvencion"|"bono", importe, desde, hasta, caduca?, dirigida_a: "todos"|"empresa", empresa_destino?, cuenta_fondos, dip_actor }
// "todos" admite beneficiarios de la entidad. "empresa" admite solo a esa empresa. Un bono exige caduca.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "subvenciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { data, error } = await a.db.rpc("plone27_convocatoria_empresa_crear", {
      p_bank: a.c.bank_id, p_cip: c.cip, p_actor: actor, p_nombre: String(b?.nombre ?? ""), p_tipo: String(b?.tipo ?? "subvencion"),
      p_importe: Number(b?.importe), p_desde: String(b?.desde ?? ""), p_hasta: String(b?.hasta ?? ""),
      p_caduca: b?.caduca ? String(b.caduca) : null, p_dirigida: String(b?.dirigida_a ?? "todos"),
      p_empresa_destino: b?.empresa_destino ? String(b.empresa_destino) : null, p_cuenta_fondos: String(b?.cuenta_fondos ?? ""),
    });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ convocatoria: data }, { status: 201 });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
