import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Cuentas del usuario (solo las suyas)
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const { data, error } = await s.db.rpc("plone27_user_accounts", { p_user: s.usuario, p_bank: s.banco });
  if (error) return respuesta(req, { error: "No se pueden cargar las cuentas" }, 500, s.cliente);
  const cuentas = (Array.isArray(data) ? data : []).map(({ id: _id, ...resto }) => resto);
  return respuesta(req, { cuentas }, 200, s.cliente);
}

// Abrir una cuenta personal propia en la entidad. Body: nombre. Idempotency-Key obligatoria.
export async function POST(req: Request) {
  const r = await sesionDe(req, "me:contratar");
  if ("err" in r) return r.err;
  const { s } = r;
  const clave = req.headers.get("idempotency-key") ?? "";
  if (!clave || clave.length > 128) return respuesta(req, { error: "Idempotency-Key obligatoria (máximo 128)" }, 400, s.cliente);
  const b = await req.json().catch(() => null);
  const { data, error } = await s.db.rpc("plone27_user_open_account", { p_user: s.usuario, p_bank: s.banco, p_nombre: String(b?.nombre ?? "") });
  if (error) return respuesta(req, { error: error.message }, 422, s.cliente);
  return respuesta(req, { cuenta: data }, 201, s.cliente);
}
