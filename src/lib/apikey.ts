import { createHash } from "crypto";
import { admin } from "./supabase";
export const hashKey = (k: string) => createHash("sha256").update(k).digest("hex");
type Client = { id: string; bank_id: string; scopes: string[]; rate_limit: number };
export async function clientFrom(req: Request, scope: string): Promise<{ err: number } | { err?: undefined; c: Client; db: ReturnType<typeof admin> }> {
  const k = req.headers.get("x-api-key"); if (!k) return { err: 401 };
  const db = admin();
  const { data: c } = await db.from("plone27_api_clients").select("id,bank_id,scopes,rate_limit").eq("key_hash", hashKey(k)).eq("active", true).maybeSingle();
  if (!c) return { err: 401 }; if (!c.scopes.includes(scope)) return { err: 403 };
  const { data: hits } = await db.rpc("plone27_rate_hit", { p_client: c.id });
  if ((hits as number) > c.rate_limit) return { err: 429 };
  return { c, db };
}
