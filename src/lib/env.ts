// Lee variables en tiempo de ejecución (acceso dinámico: no se congelan al compilar) y acepta varios nombres.
export const envAny = (names: string[]) => { for (const n of names) { const v = process.env[n]; if (v) return v; } return ""; };
export const SUPABASE_URL_NAMES = ["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL"];
export const SUPABASE_ANON_NAMES = ["NEXT_PUBLIC_SUPABASE_ANON_KEY", "SUPABASE_ANON_KEY", "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "SUPABASE_PUBLISHABLE_KEY"];
export const SUPABASE_SERVICE_NAMES = ["SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SECRET_KEY"];
