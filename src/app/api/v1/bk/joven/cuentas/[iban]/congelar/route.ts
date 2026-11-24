import { clientFrom } from "@/lib/apikey";

// Congelar o descongelar una cuenta Placeta Joven (joven:gestionar, solo Banco de La Placeta).
// Body: { congelada: boolean, motivo (>= 10 caracteres para congelar) }. Mientras esté congelada no admite movimientos.
export async function POST(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "joven:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { iban } = await params;
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  if (typeof b?.congelada !== "boolean") return Response.json({ error: "congelada debe ser true o false" }, { status: 400 });
  const { error } = await a.db.rpc("plone27_joven_congelar", {
    p_bank: a.c.bank_id, p_iban: iban, p_congelada: b.congelada, p_motivo: String(b?.motivo ?? ""), p_actor: null,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ iban, congelada: b.congelada });
}
