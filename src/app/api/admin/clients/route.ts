import { randomBytes } from "crypto";
import { staffFrom } from "@/lib/supabase";
import { hashKey } from "@/lib/apikey";
export async function POST(req: Request) {
  const s = await staffFrom(req, []); // solo admin
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  if (!b?.bank_id || !b?.name) return Response.json({ error: "bank_id y name requeridos" }, { status: 400 });
  const def = Number((await s.db.from("plone27_settings").select("value").eq("key", "api_default_rate_limit").single()).data?.value ?? 60);
  const key = "plk_" + randomBytes(24).toString("hex");
  const { error } = await s.db.from("plone27_api_clients").insert({ bank_id: b.bank_id, name: b.name, key_hash: hashKey(key),
    scopes: b.scopes ?? ["accounts:read", "transfers:write"], rate_limit: b.rate_limit ?? def });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ api_key: key, aviso: "Se muestra una sola vez" }); // en BD solo se guarda el hash
}
