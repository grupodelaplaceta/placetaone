import { staffFrom } from "@/lib/supabase";
export async function GET(req: Request) {
  const s = await staffFrom(req, ["financiero", "gestor_bancario", "auditor", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  let q = s.db.from("plone27_account_balances").select("*").order("name");
  if (s.bank) q = q.eq("bank_id", s.bank); // alcance por entidad
  const { data, error } = await q;
  return error ? Response.json({ error: error.message }, { status: 500 }) : Response.json(data);
}
