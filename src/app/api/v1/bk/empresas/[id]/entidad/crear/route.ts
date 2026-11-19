import { clientFrom } from "@/lib/apikey";

// Crear la entidad institucional de la empresa sobre una de sus cuentas y vincularla (empresas:gestionar).
// Lo pide un titular activo de la empresa. Devuelve el CIP: la cuenta elegida pasa a informarlo (cip_origen = cuenta).
// Body: { dip_actor, iban?: "PZ-…" (si se omite, la primera cuenta de empresa), nombre?: string (si se omite, el nombre de la empresa) }
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "empresas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const actor = await a.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actor.error) return Response.json({ error: actor.error.message }, { status: 422 });
  const { data, error } = await a.db.rpc("plone27_empresa_crear_entidad", { p_bank: a.c.bank_id, p_empresa: id,
    p_iban: b?.iban ? String(b.iban) : null, p_nombre: b?.nombre ? String(b.nombre) : null, p_actor: actor.data });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ cip: data, aviso: "La entidad está vinculada. Crea ahora las unidades del organigrama con POST /api/v1/bk/organigrama (accion: unidad)." }, { status: 201 });
}
