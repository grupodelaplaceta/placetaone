import { createClient } from "@supabase/supabase-js";
export const admin = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, { auth: { persistSession: false } });

export async function staffFrom(req: Request, roles: string[]) {
  const token = req.headers.get("authorization")?.replace("Bearer ", "");
  if (!token) return null;
  const db = admin();
  const { data } = await db.auth.getUser(token);
  if (!data.user) return null;
  const { data: s } = await db.from("plone27_staff").select("role,active,bank_id").eq("user_id", data.user.id).maybeSingle();
  if (!s?.active || !(s.role === "admin" || roles.includes(s.role))) return null;
  return { id: data.user.id, role: s.role as string, bank: (s.bank_id as string | null) ?? null, db };
}
