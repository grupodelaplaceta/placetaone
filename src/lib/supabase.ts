import { createClient } from "@supabase/supabase-js";
import { envAny, SUPABASE_URL_NAMES, SUPABASE_SERVICE_NAMES } from "./env";
export const admin = () =>
  createClient(envAny(SUPABASE_URL_NAMES), envAny(SUPABASE_SERVICE_NAMES), { auth: { persistSession: false } });

export async function staffFrom(req: Request, roles: string[]) {
  const token = req.headers.get("authorization")?.replace("Bearer ", "");
  if (!token) return null;
  const db = admin();
  const { data } = await db.auth.getUser(token);
  if (!data.user) return null;
  if (process.env.REQUIRE_MFA === "true") { // opcional: exige segundo factor (aal2) al personal
    try { if (JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString()).aal !== "aal2") return null; } catch { return null; }
  }
  const { data: s } = await db.from("plone27_staff").select("role,active,bank_id").eq("user_id", data.user.id).maybeSingle();
  if (!s?.active || !(s.role === "admin" || roles.includes(s.role))) return null;
  return { id: data.user.id, role: s.role as string, bank: (s.bank_id as string | null) ?? null, db };
}
