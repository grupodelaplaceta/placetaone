import { staffFrom } from "@/lib/supabase";
import { hexAleatorio } from "@/lib/apikey";

// Panel de pasarela, branding y webhooks de cada entidad. Lectura: personal de gestión. Cambios: aprobador.
// Las operaciones usan las mismas funciones que la API del banco.
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const bankId = new URL(req.url).searchParams.get("bank_id");
  if (!bankId) {
    const { data, error } = await s.db.from("plone27_banks").select("id,code,name,nombre_visible,logo_url,color_principal,texto_pie").order("name");
    return error ? Response.json({ error: error.message }, { status: 500 }) : Response.json({ bancos: data ?? [] });
  }
  const [cfg, brand, hooks, entregas] = await Promise.all([
    s.db.from("plone27_pasarela_config").select("activa,minutos_defecto,importe_maximo,destinos").eq("bank_id", bankId).maybeSingle(),
    s.db.from("plone27_banks").select("nombre_visible,logo_url,color_principal,texto_pie").eq("id", bankId).maybeSingle(),
    s.db.from("plone27_webhooks").select("id,url,events,active").eq("bank_id", bankId),
    s.db.rpc("plone27_bk_entregas_lista", { p_bank: bankId, p_estado: null, p_limite: 50 }),
  ]);
  const error = cfg.error || brand.error || hooks.error || entregas.error;
  if (error) return Response.json({ error: error.message }, { status: 500 });
  return Response.json({ config: cfg.data ?? null, branding: brand.data ?? null, webhooks: hooks.data ?? [], entregas: entregas.data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const bank = String(b?.bank_id ?? "");
  const accion = String(b?.accion ?? "");
  const fail = (m: string) => Response.json({ error: m }, { status: 422 });
  const opt = (v: unknown) => (v === undefined || v === null || String(v).trim() === "" ? null : String(v).trim());
  if (accion === "pasarela") {
    const destinos = Array.isArray(b?.destinos) ? b.destinos.map(String) : ["business", "system"];
    const r = await s.db.rpc("plone27_bk_pasarela_set", { p_bank: bank, p_activa: Boolean(b?.activa), p_minutos: Number(b?.minutos_defecto ?? 15),
      p_importe_max: Number(b?.importe_maximo ?? 50000), p_destinos: destinos });
    return r.error ? fail(r.error.message) : Response.json({ ok: true });
  }
  if (accion === "branding") {
    const r = await s.db.rpc("plone27_bk_branding_set", { p_bank: bank, p_logo: opt(b?.logo_url), p_color: opt(b?.color_principal),
      p_nombre: opt(b?.nombre_visible), p_texto: opt(b?.texto_pie) });
    return r.error ? fail(r.error.message) : Response.json({ ok: true });
  }
  if (accion === "webhook_crear") {
    const secreto = hexAleatorio(24);
    const eventos = Array.isArray(b?.eventos) ? b.eventos.map(String) : [];
    const r = await s.db.rpc("plone27_bk_webhook_crear", { p_bank: bank, p_url: String(b?.url ?? ""), p_eventos: eventos, p_secret: secreto });
    return r.error ? fail(r.error.message) : Response.json({ ok: true, secreto, id: r.data });
  }
  if (accion === "webhook_rotar") {
    const secreto = hexAleatorio(24);
    const r = await s.db.rpc("plone27_bk_webhook_rotar", { p_bank: bank, p_id: String(b?.id ?? ""), p_secret: secreto });
    return r.error ? fail(r.error.message) : Response.json({ ok: true, secreto });
  }
  if (accion === "webhook_baja") {
    const r = await s.db.rpc("plone27_bk_webhook_baja", { p_bank: bank, p_id: String(b?.id ?? "") });
    return r.error ? fail(r.error.message) : Response.json({ ok: true });
  }
  if (accion === "entrega_reintentar") {
    const r = await s.db.rpc("plone27_bk_entrega_reintentar", { p_bank: bank, p_id: Number(b?.id) });
    return r.error ? fail(r.error.message) : Response.json({ ok: true });
  }
  return Response.json({ error: "Acción no válida" }, { status: 400 });
}
