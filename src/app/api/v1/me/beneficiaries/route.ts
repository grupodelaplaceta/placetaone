import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Beneficiarios guardados del usuario
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_beneficiaries", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar los beneficiarios" }, 422, s.cliente);
  return respuesta(req, { beneficiarios: Array.isArray(data) ? data : [] }, 200, s.cliente);
}

// Guardar un beneficiario. Body: alias, iban.
export async function POST(req: Request) {
  const r = await sesionDe(req, "me:transfer");
  if ("err" in r) return r.err;
  const { s } = r;
  const b = await req.json().catch(() => null);
  const { data, error } = await s.db.rpc("plone27_user_beneficiary_add", { p_user: s.usuario, p_bank: s.banco, p_alias: String(b?.alias ?? ""), p_iban: String(b?.iban ?? "") });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { beneficiario: data }, 201, s.cliente);
}
