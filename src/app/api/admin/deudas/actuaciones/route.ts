import { staffFrom } from "@/lib/supabase";

// Historial de actuaciones sobre deudas (solo la Junta). Query: debt (opcional)
export async function GET(req: Request) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const debt = new URL(req.url).searchParams.get("debt");
  let q = s.db.from("plone27_deuda_actuaciones").select("*").order("creada", { ascending: false }).limit(200);
  if (debt) q = q.eq("debt", debt);
  const { data, error } = await q;
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ actuaciones: data ?? [] });
}
