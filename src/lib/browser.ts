import { createClient, SupabaseClient } from "@supabase/supabase-js";
let c: SupabaseClient | null = null;
// Se inicializa una vez desde /api/public-config (variables del servidor en ejecución).
export async function initSb() {
  if (c) return c;
  const j = await (await fetch("/api/public-config")).json();
  if (!j.url || !j.anonKey) throw new Error(`Faltan variables en Vercel: ${!j.url ? "NEXT_PUBLIC_SUPABASE_URL " : ""}${!j.anonKey ? "NEXT_PUBLIC_SUPABASE_ANON_KEY" : ""}`.trim());
  return (c = createClient(j.url, j.anonKey));
}
export const sb = () => { if (!c) throw new Error("Supabase no inicializado"); return c; };
