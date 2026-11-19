import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa, personaPorDip } from "@/lib/empresas";

// Catálogo de complementos de la entidad de la empresa. GET: nominas:read. POST: retribuciones:gestionar.
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "nominas:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_bk_complementos", { p_bank: a.c.bank_id, p_cip: c.cip });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ complementos: data ?? [] });
}

// Body: { codigo, nombre, tipo: "fijo" | "variable", importe_base?, dip_actor }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "retribuciones:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  try {
    const actor = await personaPorDip(a.db, String(b?.dip_actor ?? ""));
    const { data, error } = await a.db.rpc("plone27_bk_complemento_crear", { p_bank: a.c.bank_id, p_cip: c.cip, p_actor: actor,
      p_codigo: String(b?.codigo ?? ""), p_nombre: String(b?.nombre ?? ""), p_tipo: String(b?.tipo ?? "fijo"),
      p_importe: b?.importe_base == null ? null : Number(b.importe_base) });
    if (error) return Response.json({ error: error.message }, { status: 422 });
    return Response.json({ complemento: data }, { status: 201 });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 422 });
  }
}
