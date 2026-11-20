import { staffFrom } from "@/lib/supabase";

// Crear una subvención o bono (admin). Reserva el importe en la cuenta del programa.
// Body: { program, beneficiary, amount, convocatoria?, caduca? }
export async function POST(req: Request) {
  const s = await staffFrom(req, ["admin"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  const { data, error } = await s.db.rpc("plone27_grant_crear", {
    p_program: String(b?.program ?? ""), p_beneficiary: String(b?.beneficiary ?? ""), p_amount: Number(b?.amount),
    p_convocatoria: b?.convocatoria ? String(b.convocatoria) : null, p_caduca: b?.caduca ? String(b.caduca) : null, p_actor: s.id,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ subvencion: data }, { status: 201 });
}
