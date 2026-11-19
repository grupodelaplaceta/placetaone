import { clientFrom } from "@/lib/apikey";
import { cipDeEmpresa } from "@/lib/empresas";

// Conceptos de nómina de un periodo para NEXE (nominas:read). Query: periodo=AAAA-MM
// Devuelve, por persona, sus retribuciones y complementos vigentes en el periodo.
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "nominas:read");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const periodo = new URL(req.url).searchParams.get("periodo") ?? "";
  const c = await cipDeEmpresa(a.db, a.c.bank_id, id);
  if ("error" in c) return Response.json({ error: c.error }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_bk_conceptos_periodo", { p_bank: a.c.bank_id, p_cip: c.cip, p_periodo: periodo });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ periodo, conceptos: data ?? [] });
}
