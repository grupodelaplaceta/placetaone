import { createHmac, randomBytes, timingSafeEqual } from "crypto";
import { admin } from "@/lib/supabase";
import { hashKey } from "@/lib/apikey";
import { respuesta, preflight, normalizarDip } from "@/lib/sesion";
export const OPTIONS = preflight;

// Permisos que puede recibir un usuario. El banco pide cuáles; nunca puede ganar más que su cliente.
const PERMISOS_USUARIO = ["me:read", "me:transfer"];

// Crear sesión de usuario. Solo desde el servidor del banco: clave + firma HMAC + ventana de 5 minutos + nonce único.
export async function POST(req: Request) {
  if (req.headers.get("origin") || req.headers.get("sec-fetch-site")) return respuesta(req, { error: "Solo desde el servidor del banco" }, 403);
  const cruda = await req.text();
  const db = admin();
  const { data: c } = await db.from("plone27_api_clients").select("id,scopes,signing_secret,rate_limit")
    .eq("key_hash", hashKey(req.headers.get("x-client-key") ?? "")).eq("active", true).maybeSingle();
  if (!c || !c.signing_secret) return respuesta(req, { error: "No autorizado" }, 401);
  if (!c.scopes.includes("sesiones:crear")) return respuesta(req, { error: "Permiso insuficiente" }, 403, c.id);

  const ts = Number(req.headers.get("x-timestamp"));
  if (!Number.isFinite(ts) || Math.abs(Date.now() - ts) > 300000) return respuesta(req, { error: "Marca de tiempo fuera de ventana" }, 401, c.id);
  const firma = req.headers.get("x-signature") ?? "";
  const esperada = createHmac("sha256", c.signing_secret).update(`${ts}.${cruda}`).digest("hex");
  if (firma.length !== esperada.length || !timingSafeEqual(Buffer.from(firma), Buffer.from(esperada))) return respuesta(req, { error: "Firma no válida" }, 401, c.id);

  const nonce = req.headers.get("x-nonce") ?? "";
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(nonce)) return respuesta(req, { error: "Nonce no válido" }, 400, c.id);
  const { error: eNonce } = await db.from("plone27_api_nonces").insert({ client_id: c.id, nonce });
  if (eNonce) return respuesta(req, { error: "Petición repetida" }, 409, c.id);

  const { data: hits } = await db.rpc("plone27_rate_hit", { p_client: c.id });
  if (Number(hits) > Number(c.rate_limit)) return respuesta(req, { error: "Demasiadas peticiones" }, 429, c.id);

  let cuerpo: { dip?: unknown; minutos?: unknown; permisos?: unknown };
  try { cuerpo = JSON.parse(cruda); } catch { return respuesta(req, { error: "JSON no válido" }, 400, c.id); }
  const dip = normalizarDip(cuerpo.dip);
  if (!dip) return respuesta(req, { error: "DIP no válido" }, 400, c.id);
  const minutos = cuerpo.minutos === undefined ? 15 : Number(cuerpo.minutos);
  if (!Number.isInteger(minutos) || minutos < 1 || minutos > 60) return respuesta(req, { error: "minutos entre 1 y 60" }, 400, c.id);
  const pedidos = Array.isArray(cuerpo.permisos) ? cuerpo.permisos.map(String) : PERMISOS_USUARIO;
  const permisos = pedidos.filter((p) => PERMISOS_USUARIO.includes(p) && c.scopes.includes(p));
  if (permisos.length === 0) return respuesta(req, { error: "Ningún permiso de usuario concedido a este cliente" }, 403, c.id);

  const token = "pus_" + randomBytes(32).toString("hex");
  const { data: expira, error } = await db.rpc("plone27_session_open", {
    p_client: c.id, p_dip: dip, p_hash: hashKey(token), p_scopes: permisos, p_ttl: minutos });
  if (error) return respuesta(req, { error: error.message }, 422, c.id);
  return respuesta(req, { token, expira, permisos }, 201, c.id);
}

// Cerrar sesión: revoca el token actual
export async function DELETE(req: Request) {
  const m = /^Bearer (pus_[0-9a-f]{64})$/.exec(req.headers.get("authorization") ?? "");
  if (!m) return respuesta(req, { error: "Sesión requerida" }, 401);
  await admin().rpc("plone27_session_revoke", { p_hash: hashKey(m[1]) });
  return respuesta(req, { revocada: true }, 200);
}
