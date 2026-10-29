import { clientFrom, ownAccount } from "@/lib/apikey";
// La app renueva la membresía mensual de una cuenta Junior en nombre de un titular o tutor. Se cobra de la propia cuenta Junior.
export async function POST(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "memberships:write"); if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const b = await req.json().catch(() => null); if (!/^[0-9a-f-]{36}$/i.test(b?.user_id ?? "")) return Response.json({ error: "user_id (UUID del titular o tutor) requerido" }, { status: 400 });
  const id = await ownAccount(a.db, a.c.bank_id, (await params).iban); if (!id) return Response.json({ error: "No encontrada" }, { status: 404 });
  const { data, error } = await a.db.rpc("plone27_subscription_renew", { p_account: id, p_user: b.user_id, p_actor: a.c.id });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data, { status: data.renewed ? 200 : 402 }); // 402: renovación no cobrada (saldo insuficiente); la membresía pasa a past_due
}
