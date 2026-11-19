import { staffFrom } from "@/lib/supabase";
import { SCOPES_EMPRESA, altaPasarelaEmpresa, personaPorDip, rotarClaveEmpresa } from "@/lib/empresas";

// Administración de empresas de una entidad. Lectura: personal de gestión. Cambios: aprobador.
// Las acciones que requieren un titular usan dip_actor (DIP de un titular activo de la empresa).
export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const u = new URL(req.url);
  const bank = u.searchParams.get("bank_id") ?? "";
  const empresa = u.searchParams.get("empresa");
  if (u.searchParams.get("ficha") && empresa) {
    const fx = await s.db.rpc("plone27_empresa_ficha", { p_bank: bank, p_empresa: empresa });
    if (fx.error) return Response.json({ error: fx.error.message }, { status: 422 });
    const ae = await s.db.from("plone27_audit_log").select("detail").eq("action", "empresa_entidad_pendiente").eq("entity_id", empresa).order("at", { ascending: false }).limit(1).maybeSingle();
    const ultimo = (ae.data?.detail as { error?: string } | null | undefined)?.error ?? null;
    return Response.json({ ficha: fx.data ? { ...(fx.data as object), ultimo_error: ultimo } : null });
  }
  if (empresa) {
    const { data, error } = await s.db.rpc("plone27_empresa_detalle", { p_bank: bank, p_empresa: empresa });
    return error ? Response.json({ error: error.message }, { status: 422 }) : Response.json({ empresa: data });
  }
  const { data, error } = await s.db.from("plone27_empresas").select("id,nombre,identificador_fiscal,estado,creada,entidad_cip").eq("bank_id", bank).order("creada", { ascending: false });
  return error ? Response.json({ error: error.message }, { status: 500 }) : Response.json({ empresas: data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const b = await req.json().catch(() => null);
  const bank = String(b?.bank_id ?? "");
  const acc = String(b?.accion ?? "");
  const empresa = String(b?.empresa ?? "");
  const fail = (m: string) => Response.json({ error: m }, { status: 422 });
  try {
    if (acc === "anadir_cuenta") {
      const actor = b?.dip_actor ? await personaPorDip(s.db, String(b.dip_actor)) : null;
      const { data, error } = await s.db.rpc("plone27_empresa_cuenta_anadir", { p_bank: bank, p_empresa: empresa, p_iban: String(b?.iban ?? ""), p_actor: actor });
      return error ? fail(error.message) : Response.json({ ok: true, cip: data });
    }
    if (acc === "asegurar_entidad") {
      const own = await s.db.from("plone27_empresas").select("id").eq("id", empresa).eq("bank_id", bank).maybeSingle();
      if (!own.data) return fail("Empresa no encontrada en ese banco");
      const { data, error } = await s.db.rpc("plone27_empresa_asegurar_entidad", { p_empresa: empresa, p_actor: s.id });
      if (error) return fail(error.message);
      if (!data) return fail("La empresa no tiene cuentas activas. Añade una cuenta primero.");
      return Response.json({ ok: true, cip: data });
    }
    if (acc === "crear_entidad") {
      const actor = await personaPorDip(s.db, String(b?.dip_actor ?? ""));
      const { data, error } = await s.db.rpc("plone27_empresa_crear_entidad", { p_bank: bank, p_empresa: empresa, p_iban: b?.iban ? String(b.iban) : null,
        p_nombre: b?.nombre ? String(b.nombre) : null, p_actor: actor });
      return error ? fail(error.message) : Response.json({ ok: true, cip: data });
    }
    if (acc === "vincular_entidad") {
      const actor = await personaPorDip(s.db, String(b?.dip_actor ?? ""));
      const { error } = await s.db.rpc("plone27_empresa_vincular_entidad", { p_bank: bank, p_empresa: empresa, p_cip: String(b?.cip ?? ""), p_actor: actor });
      return error ? fail(error.message) : Response.json({ ok: true });
    }
    if (acc === "alta") {
      const persona = await personaPorDip(s.db, String(b?.titular_dip ?? ""));
      const { data, error } = await s.db.rpc("plone27_empresa_alta_completa", { p_bank: bank, p_nombre: String(b?.nombre ?? ""),
        p_fiscal: String(b?.identificador_fiscal ?? ""), p_persona: persona, p_ibans: Array.isArray(b?.cuentas) ? b.cuentas.map(String) : [], p_actor: s.id });
      return error ? fail(error.message) : Response.json({ ok: true, empresa: data });
    }
    if (acc === "titular_alta") {
      const persona = await personaPorDip(s.db, String(b?.dip ?? ""));
      const actor = await personaPorDip(s.db, String(b?.dip_actor ?? ""));
      const { error } = await s.db.rpc("plone27_empresa_titular_alta", { p_bank: bank, p_empresa: empresa, p_persona: persona,
        p_rol: String(b?.rol ?? ""), p_motivo: String(b?.motivo ?? ""), p_actor: actor });
      return error ? fail(error.message) : Response.json({ ok: true });
    }
    if (acc === "titular_cese") {
      const persona = await personaPorDip(s.db, String(b?.dip ?? ""));
      const actor = await personaPorDip(s.db, String(b?.dip_actor ?? ""));
      const { error } = await s.db.rpc("plone27_empresa_titular_cese", { p_bank: bank, p_empresa: empresa, p_persona: persona,
        p_motivo: String(b?.motivo ?? ""), p_actor: actor });
      return error ? fail(error.message) : Response.json({ ok: true });
    }
    if (acc === "pasarela_alta") {
      const actor = await personaPorDip(s.db, String(b?.dip_actor ?? ""));
      const scopes = Array.isArray(b?.scopes) ? b.scopes.map(String) : SCOPES_EMPRESA;
      const r = await altaPasarelaEmpresa(s.db, bank, empresa, actor, String(b?.nombre_cliente ?? "Pasarela de empresa"), scopes);
      return Response.json({ ok: true, ...r, aviso: "Guarda la clave ahora: no se vuelve a mostrar." });
    }
    if (acc === "pasarela_rotar") {
      const actor = await personaPorDip(s.db, String(b?.dip_actor ?? ""));
      const r = await rotarClaveEmpresa(s.db, bank, empresa, actor);
      return Response.json({ ok: true, ...r, aviso: "Guarda la clave ahora: no se vuelve a mostrar. La anterior ya no funciona." });
    }
    if (acc === "estado") {
      const actor = await personaPorDip(s.db, String(b?.dip_actor ?? ""));
      const { error } = await s.db.rpc("plone27_empresa_estado", { p_bank: bank, p_empresa: empresa, p_estado: String(b?.estado ?? ""),
        p_motivo: String(b?.motivo ?? ""), p_actor: actor });
      return error ? fail(error.message) : Response.json({ ok: true });
    }
    return Response.json({ error: "Acción no válida" }, { status: 400 });
  } catch (e) {
    return fail((e as Error).message);
  }
}
