import { staffFrom } from "@/lib/supabase";

// Sanciones (solo la Junta). GET: listado. POST: proponer. Body: { bank_id, tipo, iban, importe, motivo, norma, iban_destino? }
export async function GET(req: Request) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [sr, ar, dr] = await Promise.all([
    s.db.from("plone27_sanciones").select("*").order("creada", { ascending: false }).limit(200),
    s.db.from("plone27_accounts").select("id,iban"),
    s.db.from("plone27_denuncias").select("sancion"),
  ]);
  const error = [sr, ar, dr].find((x) => x.error);
  if (error) return Response.json({ error: error.error?.message ?? "Error al leer" }, { status: 422 });
  const iban = new Map<string, string>(((ar.data ?? []) as Record<string, unknown>[]).map((a) => [String(a.id), String(a.iban)]));
  const denuncias = new Map<string, number>();
  for (const d of (dr.data ?? []) as Record<string, unknown>[]) {
    const k = String(d.sancion);
    denuncias.set(k, (denuncias.get(k) ?? 0) + 1);
  }
  const sanciones = ((sr.data ?? []) as Record<string, unknown>[]).map((x) => ({
    ...x,
    cuenta_iban: iban.get(String(x.cuenta)) ?? null,
    cuenta_origen_iban: x.cuenta_origen ? iban.get(String(x.cuenta_origen)) ?? null : null,
    destino_iban: x.destino ? iban.get(String(x.destino)) ?? null : null,
    denuncias: denuncias.get(String(x.id)) ?? 0,
  }));
  return Response.json({ sanciones });
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
