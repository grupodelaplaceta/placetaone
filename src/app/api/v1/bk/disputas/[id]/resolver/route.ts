import { clientFrom } from "@/lib/apikey";

// Resolver una reclamación como banco acreedor (disputas:gestionar).
// Body: { decision: "devolucion" | "rechazada", monto?: number, operador: "id-del-operador" }
// Devoluciones de más de 1.000 Pz: dos operadores distintos (el primero deja constancia y el segundo ejecuta).
export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "disputas:gestionar");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const { id } = await params;
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_bk_disputa_resolver", { p_bank: a.c.bank_id, p_id: id, p_decision: String(b?.decision ?? ""),
    p_monto: b?.monto == null || b.monto === "" ? null : Number(b.monto), p_operador: String(b?.operador ?? "") });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json(data);
}
