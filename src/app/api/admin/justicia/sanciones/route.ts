import { staffFrom } from "@/lib/supabase";

// Sanciones (solo la Junta). GET: listado. POST: proponer. Body: { bank_id, tipo, iban, importe, motivo, norma, iban_destino? }
export async function GET(req: Request) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const { data, error } = await s.db.from("plone27_sanciones").select("*").order("creada", { ascending: false }).limit(200);
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ sanciones: data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_sancion_proponer", {
    p_bank: String(b?.bank_id ?? ""), p_tipo: String(b?.tipo ?? ""), p_iban: String(b?.iban ?? ""), p_importe: Number(b?.importe),
    p_motivo: String(b?.motivo ?? ""), p_norma: String(b?.norma ?? ""), p_iban_destino: b?.iban_destino ? String(b.iban_destino) : null, p_actor: s.id,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ sancion: data }, { status: 201 });
}
