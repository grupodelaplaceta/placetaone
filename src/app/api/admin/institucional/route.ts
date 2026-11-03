import { staffFrom } from "@/lib/supabase";

// Panel de la cuenta institucional. Lectura: auditor, gestión y aprobación. Operaciones: aprobador.
// Cada operación actúa como la persona indicada en dip_actor: se aplican sus permisos reales, no un acceso especial.
const fail = (m: string, status = 422) => Response.json({ error: m }, { status });

export async function GET(req: Request) {
  const s = await staffFrom(req, ["auditor", "gestor_bancario", "aprobador"]);
  if (!s) return fail("No autorizado", 403);
  const cip = new URL(req.url).searchParams.get("cip");
  if (!cip) {
    const { data, error } = await s.db.from("plone27_entidades")
      .select("account_id,cip,nombre,activa,solicitudes_activas,doble_firma_desde,presupuesto_anual").order("creada", { ascending: false });
    return error ? fail(error.message, 500) : Response.json({ entidades: data ?? [] });
  }
  const ent = await s.db.from("plone27_entidades")
    .select("account_id,cip,nombre,activa,solicitudes_activas,doble_firma_desde,presupuesto_anual,bank_id").eq("cip", cip).maybeSingle();
  if (ent.error) return fail(ent.error.message, 500);
  if (!ent.data) return fail("Entidad no encontrada", 404);
  const eid = ent.data.account_id as string;
  const un = await s.db.from("plone27_unidades").select("id,padre,tipo,nombre,codigo,activa").eq("entidad", eid).order("nombre");
  const ids: string[] = (un.data ?? []).map((u: { id: string }) => u.id);
  if (ids.length === 0) {
    return Response.json({ entidad: ent.data, unidades: [], presupuestos: [], meses: [], planes: [], fondos: [], gastos: [], tareas: [],
      recurrentes: [], convocatorias: [], solicitudes: [] });
  }
  const [pres, meses, planes, fondos, gastos, tareas, recur, conv, sol] = await Promise.all([
    s.db.from("plone27_presupuestos").select("unidad,ejercicio,anual").in("unidad", ids),
    s.db.from("plone27_presupuesto_meses").select("unidad,ejercicio,mes,importe").in("unidad", ids),
    s.db.from("plone27_planes_plurianuales").select("id,unidad,nombre,ejercicio_inicio,ejercicio_fin,total").in("unidad", ids),
    s.db.from("plone27_fondos").select("id,unidad,nombre,finalidad,importe,activo").in("unidad", ids),
    s.db.from("plone27_gastos").select("id,unidad,ejercicio,importe,concepto,origen,estado,fondo,fecha,creado").eq("entidad", eid).order("creado", { ascending: false }).limit(300),
    s.db.from("plone27_tareas").select("id,unidad,concepto,importe,estado,referencia_externa,creada").eq("entidad", eid).order("creada", { ascending: false }).limit(200),
    s.db.from("plone27_recurrentes").select("id,unidad,concepto,importe,periodicidad_meses,desde,hasta,activo").eq("entidad", eid),
    s.db.from("plone27_convocatorias").select("id,nombre,importe,desde,hasta,estado").eq("entidad", eid),
    s.db.from("plone27_solicitudes_unidad").select("id,unidad,tipo,importe,referencia,convocatoria,nueva_fecha,justificacion,estado,creada").eq("entidad", eid).order("creada", { ascending: false }).limit(200),
  ]);
  const error = pres.error || meses.error || planes.error || fondos.error || gastos.error || tareas.error || recur.error || conv.error || sol.error;
  if (error) return fail(error.message, 500);
  return Response.json({ entidad: ent.data, unidades: un.data ?? [], presupuestos: pres.data ?? [], meses: meses.data ?? [],
    planes: planes.data ?? [], fondos: fondos.data ?? [], gastos: gastos.data ?? [], tareas: tareas.data ?? [],
    recurrentes: recur.data ?? [], convocatorias: conv.data ?? [], solicitudes: sol.data ?? [] });
}

export async function POST(req: Request) {
  const s = await staffFrom(req, ["aprobador"]);
  if (!s) return fail("No autorizado", 403);
  const b = await req.json().catch(() => null);
  const cip = String(b?.cip ?? "");
  const accion = String(b?.accion ?? "");
  const ent = await s.db.from("plone27_entidades").select("bank_id").eq("cip", cip).maybeSingle();
  if (!ent.data) return fail("Entidad no encontrada", 404);
  const actorRes = await s.db.rpc("plone27_persona", { p_dip: String(b?.dip_actor ?? "") });
  if (actorRes.error) return fail(actorRes.error.message);
  const bank = ent.data.bank_id as string;
  const cipv = cip;
  const actor = actorRes.data as string;
  const num = (v: unknown) => Number(v);
  const txt = (v: unknown) => String(v ?? "");
  const opt = (v: unknown) => (v === undefined || v === null || v === "" ? null : String(v));
  switch (accion) {
    case "presupuesto_anual": {
      const r = await s.db.rpc("plone27_presupuesto_fijar", { p_bank: bank, p_cip: cipv, p_actor: actor, p_unidad: txt(b?.unidad), p_ejercicio: num(b?.ejercicio), p_importe: num(b?.importe) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "presupuesto_general": {
      const r = await s.db.rpc("plone27_entidad_presupuesto_fijar", { p_bank: bank, p_cip: cipv, p_actor: actor, p_importe: num(b?.importe) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "presupuesto_mes": {
      const r = await s.db.rpc("plone27_presupuesto_mes_fijar", { p_bank: bank, p_cip: cipv, p_actor: actor, p_unidad: txt(b?.unidad), p_ejercicio: num(b?.ejercicio), p_mes: num(b?.mes), p_importe: num(b?.importe) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "plan_plurianual": {
      const r = await s.db.rpc("plone27_plan_plurianual_crear", { p_bank: bank, p_cip: cipv, p_actor: actor, p_unidad: txt(b?.unidad), p_nombre: txt(b?.nombre), p_inicio: num(b?.inicio), p_fin: num(b?.fin), p_total: num(b?.total) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "gasto_proponer": {
      const r = await s.db.rpc("plone27_gasto_proponer", { p_bank: bank, p_cip: cipv, p_actor: actor, p_unidad: txt(b?.unidad), p_ejercicio: num(b?.ejercicio), p_importe: num(b?.importe), p_concepto: txt(b?.concepto), p_iban: opt(b?.iban), p_key: null });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "gasto_fondo": {
      const r = await s.db.rpc("plone27_gasto_asignar_fondo", { p_bank: bank, p_gasto: txt(b?.gasto), p_actor: actor, p_fondo: txt(b?.fondo) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true });
    }
    case "gasto_aprobar": {
      const r = await s.db.rpc("plone27_gasto_aprobar", { p_bank: bank, p_gasto: txt(b?.gasto), p_actor: actor });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "gasto_rechazar": {
      const r = await s.db.rpc("plone27_gasto_rechazar", { p_bank: bank, p_gasto: txt(b?.gasto), p_actor: actor, p_motivo: txt(b?.motivo) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true });
    }
    case "gasto_pagar": {
      const r = await s.db.rpc("plone27_gasto_pagar", { p_bank: bank, p_gasto: txt(b?.gasto), p_actor: actor });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "tarea_validar": {
      const r = await s.db.rpc("plone27_tarea_validar", { p_bank: bank, p_tarea: txt(b?.tarea), p_actor: actor });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "tarea_pagar": {
      const r = await s.db.rpc("plone27_tarea_pagar", { p_bank: bank, p_tarea: txt(b?.tarea), p_actor: actor });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "tarea_rechazar": {
      const r = await s.db.rpc("plone27_tarea_rechazar", { p_bank: bank, p_tarea: txt(b?.tarea), p_actor: actor, p_motivo: txt(b?.motivo) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true });
    }
    case "nomina_periodo": {
      const r = await s.db.rpc("plone27_nomina_periodo", { p_bank: bank, p_cip: cipv, p_actor: actor, p_periodo: txt(b?.periodo) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "fondo_crear": {
      const r = await s.db.rpc("plone27_fondo_crear", { p_bank: bank, p_cip: cipv, p_actor: actor, p_unidad: txt(b?.unidad), p_nombre: txt(b?.nombre), p_finalidad: txt(b?.finalidad), p_importe: num(b?.importe) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "recurrente_crear": {
      const r = await s.db.rpc("plone27_recurrente_crear", { p_bank: bank, p_cip: cipv, p_actor: actor, p_unidad: txt(b?.unidad), p_concepto: txt(b?.concepto), p_importe: num(b?.importe), p_iban: opt(b?.iban), p_meses: num(b?.meses), p_desde: txt(b?.desde), p_hasta: opt(b?.hasta) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "recurrentes_generar": {
      const r = await s.db.rpc("plone27_recurrentes_generar", { p_bank: bank, p_cip: cipv, p_actor: actor, p_periodo: txt(b?.periodo) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "convocatoria_crear": {
      const r = await s.db.rpc("plone27_convocatoria_crear", { p_bank: bank, p_cip: cipv, p_actor: actor, p_nombre: txt(b?.nombre), p_importe: num(b?.importe), p_desde: txt(b?.desde), p_hasta: txt(b?.hasta) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "config": {
      const r = await s.db.rpc("plone27_entidad_config", { p_bank: bank, p_cip: cipv, p_actor: actor, p_solicitudes: Boolean(b?.solicitudes), p_doble_firma: b?.doble_firma ? num(b.doble_firma) : null });
      return r.error ? fail(r.error.message) : Response.json({ ok: true });
    }
    case "solicitud_crear": {
      const r = await s.db.rpc("plone27_solicitud_crear", { p_bank: bank, p_cip: cipv, p_actor: actor, p_unidad: txt(b?.unidad), p_tipo: txt(b?.tipo), p_importe: b?.importe ? num(b.importe) : null, p_referencia: opt(b?.referencia), p_nueva_fecha: opt(b?.nueva_fecha), p_justificacion: txt(b?.justificacion), p_convocatoria: opt(b?.convocatoria) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true, resultado: r.data });
    }
    case "solicitud_resolver": {
      const r = await s.db.rpc("plone27_solicitud_resolver", { p_bank: bank, p_solicitud: txt(b?.solicitud), p_actor: actor, p_decision: txt(b?.decision), p_resolucion: txt(b?.resolucion) });
      return r.error ? fail(r.error.message) : Response.json({ ok: true });
    }
    default:
      return fail("Acción no válida", 400);
  }
}
