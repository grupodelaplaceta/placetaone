import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Borrar un beneficiario propio
export async function DELETE(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const r = await sesionDe(req, "me:transfer");
  if ("err" in r) return r.err;
  const { s } = r;
  const { id } = await params;
  const { error } = await s.db.rpc("plone27_user_beneficiary_delete", { p_user: s.usuario, p_bank: s.banco, p_id: id });
  if (error) return respuesta(req, { error: "Beneficiario no encontrado" }, 404, s.cliente);
  return respuesta(req, { borrado: true }, 200, s.cliente);
}
