import { admin } from "./supabase";
import { hashKey } from "./apikey";

// Autenticación y aislamiento de las APIs de usuario (/api/v1/me/...).
// El usuario SIEMPRE sale del token de sesión. Ninguna petición puede indicar «para qué usuario» actúa.
export type Db = ReturnType<typeof admin>;
export type Sesion = { usuario: string; cliente: string; banco: string; permisos: string[]; db: Db };

// Respuesta JSON. Añade CORS solo si el origen está autorizado para el cliente de la sesión.
export async function respuesta(req: Request, cuerpo: unknown, status = 200, clienteId?: string | null): Promise<Response> {
  const origen = req.headers.get("origin");
  const cab: Record<string, string> = { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", vary: "Origin" };
  if (origen && clienteId) {
    const { data: ok } = await admin().rpc("plone27_origen_permitido", { p_origin: origen, p_client: clienteId });
    if (ok === true) cab["access-control-allow-origin"] = origen;
  }
  return new Response(JSON.stringify(cuerpo), { status, headers: cab });
}

// Comprobación previa del navegador: solo responde a orígenes registrados por algún cliente.
export async function preflight(req: Request): Promise<Response> {
  const origen = req.headers.get("origin") ?? "";
  const { data: ok } = origen ? await admin().rpc("plone27_origen_permitido", { p_origin: origen, p_client: null }) : { data: false };
  if (ok !== true) return new Response(null, { status: 403, headers: { vary: "Origin" } });
  return new Response(null, { status: 204, headers: {
    "access-control-allow-origin": origen, "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
    "access-control-allow-headers": "authorization,content-type,idempotency-key", "access-control-max-age": "600", vary: "Origin" } });
}

// Valida el token pus_… y el permiso pedido. Devuelve la sesión o la respuesta de error ya construida.
export async function sesionDe(req: Request, permiso: string): Promise<{ s: Sesion } | { err: Response }> {
  const m = /^Bearer (pus_[0-9a-f]{64})$/.exec(req.headers.get("authorization") ?? "");
  if (!m) return { err: await respuesta(req, { error: "Sesión requerida" }, 401) };
  const db = admin();
  const { data } = await db.rpc("plone27_session_check", { p_hash: hashKey(m[1]) });
  const fila = Array.isArray(data) ? data[0] : null;
  if (!fila) return { err: await respuesta(req, { error: "Sesión caducada o revocada" }, 401) };
  if (!fila.scopes?.includes(permiso)) return { err: await respuesta(req, { error: "Permiso insuficiente" }, 403, fila.client_id) };
  const { data: hits } = await db.rpc("plone27_rate_hit", { p_client: fila.client_id });
  if (Number(hits) > Number(fila.rate_limit)) return { err: await respuesta(req, { error: "Demasiadas peticiones" }, 429, fila.client_id) };
  return { s: { usuario: fila.user_id, cliente: fila.client_id, banco: fila.bank_id, permisos: fila.scopes, db } };
}

// Resuelve un IBAN solo entre las cuentas del usuario. Si no es suya, devuelve null (sin revelar si existe).
export async function cuentaDelUsuario(s: Sesion, iban: string): Promise<string | null> {
  const { data } = await s.db.rpc("plone27_user_accounts", { p_user: s.usuario, p_bank: s.banco });
  const lista: { id: string; iban: string }[] = Array.isArray(data) ? data : [];
  return lista.find((c) => c.iban === iban)?.id ?? null;
}

// El DIP se normaliza (sin espacios ni guiones, en mayúsculas). Devuelve null si no tiene un formato válido.
export function normalizarDip(valor: unknown): string | null {
  if (typeof valor !== "string") return null;
  const d = valor.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
  return /^[A-Z0-9]{5,20}$/.test(d) ? d : null;
}
