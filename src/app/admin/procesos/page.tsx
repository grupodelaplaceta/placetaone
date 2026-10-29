"use client";
import { useState } from "react";
import { api } from "@/lib/api";
const P: [string, string, object, string][] = [
  ["plone27_charge_product_fees", "Cobrar cuotas mensuales de productos", {}, "Cobra una vez al mes a cada cuenta con producto; repetirlo no duplica."],
  ["plone27_accrue_interest", "Devengar intereses del crédito interno", {}, "Interés mensual sobre descubiertos; una sola vez por cuenta y mes."],
  ["plone27_subscriptions_sweep", "Renovar membresías Junior y marcar vencidas", {}, "Renueva automáticamente las que toca, pasa a «pendiente» las vencidas y a «expirada» las que superan la gracia."],
  ["plone27_run_scheduled", "Ejecutar programadas y recurrentes vencidas", {}, "Ejecuta lo pendiente; los fallos quedan como incidencias."],
  ["plone27_apply_late_penalties", "Aplicar recargos por mora", {}, "Solo actúa si lo habilitas en Configuración y hay norma autorizada."],
  ["plone27_cash_forecast", "Previsión de caja a 30 días", { p_days: 30 }, "Programadas, impuestos por vencer y reembolsos pendientes."],
  ["plone27_cash_forecast", "Previsión de caja a 90 días", { p_days: 90 }, ""]];
export default function Procesos() {
  const [out, setOut] = useState("");
  const run = async (fn: string, l: string, args: object) => { if (!confirm(`${l}?`)) return; try { setOut(JSON.stringify((await api(`/api/rpc/${fn}`, "POST", args)).result, null, 2)); } catch (e) { setOut((e as Error).message); } };
  return (<><h1>Procesos</h1><p>Tareas que se lanzan a mano desde aquí (o desde una tarea programada).</p>
    {P.map(([fn, l, a, d]) => <section key={l} style={{ background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 12 }}><button onClick={() => run(fn, l, a)}>{l}</button> <small style={{ color: "#777" }}>{d}</small></section>)}
    <pre style={{ background: "#fff", padding: 12, overflow: "auto" }}>{out}</pre></>);
}
