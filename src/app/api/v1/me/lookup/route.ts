import { sesionDe, respuesta, preflight } from "@/lib/sesion";
export const OPTIONS = preflight;

// Comprobar un IBAN antes de transferir: existencia, entidad y titular abreviado. ?iban=
export async function GET(req: Request) {
  const r = await sesionDe(req, "me:read");
  if ("err" in r) return r.err;
  const { s } = r;
  const iban = new URL(req.url).searchParams.get("iban") ?? "";
  if (!iban || iban.length > 40) return respuesta(req, { error: "iban obligatorio" }, 400, s.cliente);
  const { data, error } = await s.db.rpc("plone27_lookup_iban", { p_iban: iban });
  if (error) return respuesta(req, { error: "No se puede comprobar el IBAN" }, 422, s.cliente);
  return respuesta(req, data ?? { existe: false }, 200, s.cliente);
}
