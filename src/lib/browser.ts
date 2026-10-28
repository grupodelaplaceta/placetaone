import { createClient, SupabaseClient } from "@supabase/supabase-js";
let c: SupabaseClient | null = null;
// Se crea al primer uso en el navegador (no al compilar), para que el build no dependa de las variables de entorno.
export const sb = () => (c ??= createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!));
