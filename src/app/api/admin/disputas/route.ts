import { staffFrom } from "@/lib/supabase";

// Reclamaciones de deudas y parámetros de plazos. Lectura: personal de gestión. Cambios: aprobador.
// Resolver: { accion: "resolver", id, decision: "devolucion" | "rechazada", monto? }
// Parámetro: { accion: "parametro", clave, valor }
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [disp, par] = await Promise.all([
    s.db.from("plone27_disputas").select("id,debt_id,account_id,monto_reclamado,monto_devuelto,motivo,estado,aprobada_1,aprobada_2,plazo_resolucion,creada")
      .order("creada", { ascending: false }).limit(200),
    s.db.from("plone27_parametros").select("clave,valor,actualizado"),
  ]);
  const error = disp.error || par.error;
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json({ disputas: disp.data ?? [], parametros: par.data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  if (b?.accion === "resolver") {
    const { data, error } = await s.db.rpc("plone27_disputa_resolver", { p_id: String(b?.id ?? ""), p_decision: String(b?.decision ?? ""),
      p_monto: b?.monto == null || b.monto === "" ? null : Number(b.monto), p_actor: s.id });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ ok: true, resultado: data });
  }
  if (b?.accion === "parametro") {
    const { error } = await s.db.rpc("plone27_parametro_set", { p_clave: String(b?.clave ?? ""), p_valor: Number(b?.valor), p_actor: s.id });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ ok: true });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
