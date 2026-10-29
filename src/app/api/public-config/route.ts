import { envAny, SUPABASE_URL_NAMES, SUPABASE_ANON_NAMES } from "@/lib/env";
export const dynamic = "force-dynamic";
// Configuración pública del navegador (URL y clave anon: públicas por diseño). Nunca devuelve la clave de servicio.
export async function GET() {
  const url = envAny(SUPABASE_URL_NAMES), anonKey = envAny(SUPABASE_ANON_NAMES);
  return Response.json({ url: url || null, anonKey: anonKey || null });
}
