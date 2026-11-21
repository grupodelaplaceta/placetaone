import { randomBytes } from "crypto";
import { staffFrom } from "@/lib/supabase";
import { hashKey } from "@/lib/apikey";
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const s = await staffFrom(req, []); if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const key = "plk_" + randomBytes(24).toString("hex");
  const { data, error } = await s.db.from("plone27_api_clients").update({ key_hash: hashKey(key) }).eq("id", (await params).id).select("id");
  if (error || !data?.length) return Response.json({ error: "Cliente no encontrado" }, { status: 404 });
  await s.db.from("plone27_audit_log").insert({ actor: s.id, action: "api_key_rotated", entity: "api_client", entity_id: data[0].id });
  return Response.json({ api_key: key, aviso: "La clave anterior queda invalidada. Se muestra una sola vez." });
}
