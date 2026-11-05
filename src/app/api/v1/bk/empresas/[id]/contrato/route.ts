import { clientFrom } from "@/lib/apikey";

// Contrato vigente de la empresa, sin claves (empresas:gestionar)
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const { data, error } = await a.db.rpc("plone27_empresa_contrato_actual", { p_bank: a.c.bank_id, p_empresa: id });
  if (error) return Response.json({ error: "No se puede consultar el contrato" }, { status: 422 });
  if (!data) return Response.json({ error: "La empresa no tiene contrato" }, { status: 404 });
  return Response.json(data);
}
