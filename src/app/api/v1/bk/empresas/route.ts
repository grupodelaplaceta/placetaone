import { clientFrom } from "@/lib/apikey";

// Empresas de la entidad (empresas:gestionar). Alta con su titular inicial y sus cuentas de empresa.
export async function GET(req: Request) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { data, error } = await a.db.from("plone27_empresas").select("id,nombre,identificador_fiscal,estado,creada").eq("bank_id", a.c.bank_id).order("creada", { ascending: false });
  if (error) return Response.json({ error: "No se pueden listar las empresas" }, { status: 422 });
  return Response.json({ empresas: data ?? [] });
}

// Body: { nombre, identificador_fiscal, titular_dip, cuentas: ["PZ-…", …] }
export async function POST(req: Request) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null);
  const persona = await a.db.rpc("plone27_persona", { p_dip: String(b?.titular_dip ?? "") });
  if (persona.error) return Response.json({ error: persona.error.message }, { status: 422 });
  const cuentas = Array.isArray(b?.cuentas) ? b.cuentas.map(String) : [];
  const { data, error } = await a.db.rpc("plone27_empresa_alta_completa", { p_bank: a.c.bank_id, p_nombre: String(b?.nombre ?? ""),
    p_fiscal: String(b?.identificador_fiscal ?? ""), p_persona: persona.data, p_ibans: cuentas, p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ empresa: data }, { status: 201 });
}
