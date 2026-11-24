import { clientFrom } from "@/lib/apikey";

// Pasar la cuenta Junior de una persona a Placeta Joven (joven:gestionar, solo Banco de La Placeta).
// Solo a partir de 16 años cumplidos (según la fecha de nacimiento de su ficha junior).
// Body: { dip }. La misma cuenta conserva IBAN, saldo e historial.
export async function POST(req: Request) {
  const a = await clientFrom(req, "joven:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await a.db.rpc("plone27_joven_promover", { p_bank: a.c.bank_id, p_dip: String(b?.dip ?? ""), p_actor: null });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data, { status: 201 });
}
