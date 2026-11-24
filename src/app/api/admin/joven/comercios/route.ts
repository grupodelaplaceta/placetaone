import { staffFrom } from "@/lib/supabase";

// Marcar o quitar una empresa como comercio Placeta Joven (solo la Junta). Body: { iban, activo }
export async function POST(req: Request) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  if (typeof b?.activo !== "boolean") return Response.json({ error: "activo debe ser true o false" }, { status: 400 });
  const { error } = await s.db.rpc("plone27_joven_comercio_marcar", { p_iban: String(b?.iban ?? ""), p_activo: b.activo, p_actor: s.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ ok: true });
}
