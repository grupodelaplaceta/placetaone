import { staffFrom } from "@/lib/supabase";

// Categorías de comercio (las asigna Placeta). Lectura: personal de gestión. Cambios: aprobador.
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const [cat, com] = await Promise.all([
    s.db.from("plone27_categorias").select("codigo,nombre,activa").order("codigo"),
    s.db.rpc("plone27_bk_comercios", {}),
  ]);
  const error = cat.error || com.error;
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json({ categorias: cat.data ?? [], comercios: com.data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  if (b?.accion === "categoria_set") {
    const { error } = await s.db.rpc("plone27_categoria_set", { p_codigo: String(b?.codigo ?? ""), p_nombre: String(b?.nombre ?? ""), p_activa: Boolean(b?.activa), p_actor: s.id });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ ok: true });
  }
  if (b?.accion === "comercio_categoria") {
    const { error } = await s.db.rpc("plone27_cuenta_categoria_set", { p_iban: String(b?.iban ?? ""), p_categoria: b?.categoria ? String(b.categoria) : null, p_actor: s.id });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ ok: true });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
