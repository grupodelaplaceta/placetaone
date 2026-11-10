import { clientFrom } from "@/lib/apikey";

// Crear o reutilizar la entidad institucional de la empresa (empresas:gestionar). La empresa es su entidad.
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const own = await a.db.from("plone27_empresas").select("id").eq("id", id).eq("bank_id", a.c.bank_id).maybeSingle();
  if (!own.data) return Response.json({ error: "Empresa no encontrada en tu entidad" }, { status: 404 });
  const { data, error } = await a.db.rpc("plone27_empresa_asegurar_entidad", { p_empresa: id, p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  if (!data) return Response.json({ error: "La empresa no tiene cuentas activas. Añade una cuenta primero." }, { status: 422 });
  return Response.json({ cip: data });
}
