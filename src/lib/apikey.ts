import { createHash } from "crypto";
import { admin } from "./supabase";
export const hashKey = (k: string) => createHash("sha256").update(k).digest("hex");
type Client = { id: string; bank_id: string; scopes: string[]; rate_limit: number };
export async function clientFrom(req: Request, scope: string): Promise<{ err: 401 | 403 | 429 } | { err?: undefined; c: Client; db: ReturnType<typeof admin> }> {
  const k = req.headers.get("x-api-key"); if (!k) return { err: 401 };
  // Las claves de servidor no se usan desde navegadores: si llega un origen o metadatos de navegador, se rechaza.
  if (req.headers.get("origin") || req.headers.get("sec-fetch-site")) return { err: 403 };
  const db = admin();
  const { data: c } = await db.from("plone27_api_clients").select("id,bank_id,scopes,rate_limit").eq("key_hash", hashKey(k)).eq("active", true).maybeSingle();
  if (!c) return { err: 401 }; if (!c.scopes.includes(scope)) return { err: 403 };
  const { data: hits } = await db.rpc("plone27_rate_hit", { p_client: c.id });
  if ((hits as number) > c.rate_limit) return { err: 429 };
  return { c, db };
}
// Cuenta de la propia entidad del cliente (null si no existe o es de otra entidad)
export async function ownAccount(db: ReturnType<typeof admin>, bankId: string, iban: string) {
  const { data } = await db.from("plone27_accounts").select("id,bank_id").eq("iban", iban).maybeSingle();
  return data && data.bank_id === bankId ? data.id as string : null;
}

// Bytes aleatorios en hexadecimal. Usa la API Web Crypto (sin depender de la versión de los tipos de Node).
export function hexAleatorio(bytes: number): string {
  return Array.from(globalThis.crypto.getRandomValues(new Uint8Array(bytes)), (x) => x.toString(16).padStart(2, "0")).join("");
}

// Código numérico de 6 dígitos sin sesgo (rechaza valores fuera del múltiplo de 1.000.000).
export function codigoVerificacion(): string {
  const v = new Uint32Array(1);
  let n: number;
  do { globalThis.crypto.getRandomValues(v); n = v[0]; } while (n >= 4294000000);
  return String(n % 1000000).padStart(6, "0");
}
