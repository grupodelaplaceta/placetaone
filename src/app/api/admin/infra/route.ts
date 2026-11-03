import { staffFrom } from "@/lib/supabase";
// Foto de toda la infraestructura para el panel de /admin/infraestructura. Solo lectura.
const ROLES = ["auditor", "financiero", "fiscal", "aprobador", "gestor_bancario", "financiacion"];
const KEYS = ["smi_mensual_completa_pz", "rbu_semanal_pz", "capitalia_asume_impuestos_junior", "iva_criterio",
  "iva_umbral_fraccionamiento", "iva_patron_pagadores", "demora_habilitada", "demora_anual_pct", "autocobro_habilitado", "late_penalty_enabled", "interes_anual_pct"];
type R = Record<string, any>;
const contar = (rows: R[], k: string) => rows.reduce((m: Record<string, number>, r) => { const v = String(r[k]); m[v] = (m[v] ?? 0) + 1; return m; }, {});
const sumar = (rows: R[], f: (r: R) => number) => rows.reduce((a, r) => a + f(r), 0);

export async function GET(req: Request) {
  const s = await staffFrom(req, ROLES);
  if (!s) return Response.json({ error: "No autorizado" }, { status: 403 });
  const db = s.db;
  const res: any[] = await Promise.all([
    db.from("plone27_accounts").select("id,iban,name,kind,status,collectable"),        // 0
    db.from("plone27_banks").select("id,code,name,status,main_account,tax_account"),  // 1
    db.from("plone27_institutional_accounts").select("account_id,motivo,puede_operar_junior,aprobado_por"), // 2
    db.from("plone27_tax_rules").select("id,code,name,collector_account,max_rate"),   // 3
    db.from("plone27_tax_rule_versions").select("rule_id,status"),                     // 4
    db.from("plone27_tax_receipts").select("status,amount,paid_amount"),              // 5
    db.from("plone27_incidents").select("kind").eq("status", "open"),                  // 6
    db.from("plone27_plans").select("kind,status"),                                    // 7
    db.from("plone27_plan_items").select("status"),                                    // 8
    db.from("plone27_rbu_bonuses").select("status,amount"),                            // 9
    db.from("plone27_contracts").select("status,gross_monthly"),                       // 10
    db.from("plone27_payslips").select("net"),                                         // 11
    db.from("plone27_config").select("key,value"),                                     // 12
    db.from("plone27_iva_findings").select("status,severity,kind,amount,iva_due"),    // 13
    db.from("plone27_sales").select("base,iva,origin"),                                // 14
    db.from("plone27_settings").select("key,value").in("key", KEYS),                   // 15
    db.rpc("plone27_certification_report"),                                            // 16
  ]);
  const get = (i: number): R[] => res[i]?.data ?? [];
  const accs = get(0), banks = get(1), inst = get(2), rules = get(3), vers = get(4), recs = get(5);
  const ivaF = get(13), ventas = get(14);
  const cfg: Record<string, string> = Object.fromEntries(get(12).map((c) => [c.key, c.value]));
  const ajustes: Record<string, unknown> = Object.fromEntries(get(15).map((c) => [c.key, c.value]));
  const ibanDe = new Map(accs.map((a) => [a.id, a.iban]));
  const nombreDe = new Map(accs.map((a) => [a.id, a.name]));
  const etiqueta = (id: string | null | undefined) => (id ? `${ibanDe.get(id) ?? "?"} · ${nombreDe.get(id) ?? ""}` : "sin asignar");
  const pendientes = recs.filter((r) => r.status === "issued" || r.status === "partial");
  const abiertos = ivaF.filter((h) => h.status === "abierto");
  const capitalia = banks.find((b) => b.id === cfg.entidad_capitalia);
  const certificacion = res[16]?.data ?? {};
  const planes = get(7);

  return Response.json({
    entidades: {
      total: banks.length, activas: banks.filter((b) => b.status === "active").length,
      sin_cuenta_principal: banks.filter((b) => b.status === "active" && !b.main_account).length,
      lista: banks.map((b) => ({ codigo: b.code, nombre: b.name, estado: b.status, principal: etiqueta(b.main_account), impuestos: etiqueta(b.tax_account ?? b.main_account) })),
    },
    cuentas: {
      total: accs.length, activas: accs.filter((a) => a.status === "active").length, por_tipo: contar(accs, "kind"),
      no_embargables: accs.filter((a) => !a.collectable).length,
      lista: accs.map((a) => ({ id: a.id, etiqueta: `${a.iban} · ${a.name} (${a.kind})` })),
    },
    institucionales: {
      total: inst.length, sin_aprobador: inst.filter((i) => !i.aprobado_por).length, junior: inst.filter((i) => i.puede_operar_junior).length,
      lista: inst.map((i) => ({ cuenta: i.account_id, etiqueta: etiqueta(i.account_id), motivo: i.motivo, junior: i.puede_operar_junior, aprobada: !!i.aprobado_por })),
    },
    impuestos: {
      reglas: rules.map((r) => ({ id: r.id, codigo: r.code, nombre: r.name, destino_id: r.collector_account, destino: etiqueta(r.collector_account),
        publicadas: vers.filter((v) => v.rule_id === r.id && v.status === "published").length,
        borradores: vers.filter((v) => v.rule_id === r.id && v.status === "draft").length })),
      por_destino: rules.reduce((m: Record<string, number>, r) => { const k = etiqueta(r.collector_account); m[k] = (m[k] ?? 0) + 1; return m; }, {}),
      versiones: { publicadas: vers.filter((v) => v.status === "published").length, borrador: vers.filter((v) => v.status === "draft").length },
    },
    recibos: { por_estado: contar(recs, "status"), pendiente_importe: sumar(pendientes, (r) => Number(r.amount) - Number(r.paid_amount)) },
    certificados: certificacion,
    incidencias: contar(get(6), "kind"),
    planes: { activos: planes.filter((p) => p.status === "active").length, por_tipo: contar(planes, "kind"), cuotas_pendientes: get(8).filter((i) => i.status === "pending").length },
    rbu: { por_estado: contar(get(9), "status"), importe_disponible: sumar(get(9).filter((b) => b.status === "available"), (b) => Number(b.amount)) },
    nominas: { contratos_activos: get(10).filter((c) => c.status === "active").length, nominas_emitidas: get(11).length, neto_total: sumar(get(11), (p) => Number(p.net)) },
    iva: {
      hallazgos_por_estado: contar(ivaF, "status"), abiertos: abiertos.length,
      importe_abierto: sumar(abiertos, (h) => Number(h.amount)), iva_abierto: sumar(abiertos, (h) => Number(h.iva_due ?? 0)),
      por_severidad: contar(abiertos, "severity"), ventas: { operaciones: ventas.length, base: sumar(ventas, (v) => Number(v.base)), iva: sumar(ventas, (v) => Number(v.iva ?? 0)) },
    },
    junior: { cuentas: accs.filter((a) => a.kind === "junior").length, capitalia: capitalia ? capitalia.name : "sin designar" },
    ajustes,
    configuracion: {
      cuenta_tributos: etiqueta(cfg.cuenta_tributos), cuenta_tributos_id: cfg.cuenta_tributos ?? null,
      cuenta_rbu_origen: etiqueta(cfg.cuenta_rbu_origen ?? cfg.cuenta_reserva), cuenta_rbu_origen_id: cfg.cuenta_rbu_origen ?? null,
      cuenta_reserva: etiqueta(cfg.cuenta_reserva), cuenta_placeta_junior: etiqueta(cfg.cuenta_placeta_junior),
    },
    listas: { bancos: banks.map((b) => ({ id: b.id, nombre: `${b.code} · ${b.name}` })) },
  });
}
