import { clientFrom } from "@/lib/apikey";

// Ficha de una empresa: titulares, cuentas, pasarela y versión del contrato (empresas:gestionar)
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { data, error } = await a.db.rpc("plone27_empresa_detalle", { p_bank: a.c.bank_id, p_empresa: id });
  if (error) return Response.json({ error: "No se puede consultar la empresa" }, { status: 422 });
  if (!data) return Response.json({ error: "Empresa no encontrada" }, { status: 404 });
  return Response.json(data);
}
