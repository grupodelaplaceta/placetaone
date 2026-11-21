"use client";
import { Resource } from "../Resource";
const K = ["Personal", "Empresa", "Compartida", "Junior", "Sistema"];
const M: [string, string[]][] = [
  ["Descubierto / crédito interno", ["Con producto de crédito", "Con producto de crédito", "Con producto de crédito", "✗ Nunca", "Sí"]],
  ["Tarjeta de crédito", ["Sí", "Sí", "Sí", "✗ Nunca", "—"]],
  ["Enviar a cuentas de clientes habituales", ["Sí", "Sí", "Sí", "✗ Bloqueado", "Sí"]],
  ["Recibir de cuentas de clientes habituales", ["Sí", "Sí", "Sí", "✗ Bloqueado", "Sí"]],
  ["Operar con otras Junior y con el sistema", ["Sí", "Sí", "Sí", "Sí", "Sí"]],
  ["Límites de control parental (ficha Junior)", ["—", "—", "—", "Heredados del cliente", "—"]],
  ["Membresía mensual con renovación por API", ["—", "—", "—", "Obligatoria", "—"]]];
export default function Cuentas() {
  return (<><h1>Cuentas y saldos</h1>
    <section style={{ background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16, overflowX: "auto" }}><h2 style={{ marginTop: 0 }}>Compatibilidad por tipo de cuenta</h2>
      <table style={{ width: "100%", fontSize: 13, borderCollapse: "collapse" }}><thead><tr><th style={{ textAlign: "left" }}>Función</th>{K.map(k => <th key={k}>{k}</th>)}</tr></thead>
        <tbody>{M.map(([f, v]) => <tr key={f}><td style={{ padding: 6, borderTop: "1px solid #eee" }}>{f}</td>{v.map((x, i) => <td key={i} style={{ padding: 6, borderTop: "1px solid #eee", textAlign: "center", background: i === 3 ? "#fff8e6" : undefined, color: x.startsWith("✗") ? "#a33" : undefined }}>{x}</td>)}</tr>)}</tbody></table>
      <p style={{ color: "#555", marginBottom: 0 }}>Estas reglas las aplica la base de datos en cada movimiento: no dependen de la pantalla ni de la aplicación que use la API.</p></section>
    <Resource res="balances" title="Todas las cuentas" cols={[{ k: "name", l: "Nombre" }, { k: "kind", l: "Tipo" }, { k: "status", l: "Estado" }, { k: "booked", l: "Saldo contable" }, { k: "reserved", l: "Reservado" }]} href={r => `/admin/cuentas/${r.account_id}`} />
    <Resource res="subscriptions" title="Membresías Junior (renovación mensual)" help="Se renuevan desde la app con POST /api/v1/accounts/{iban}/membership/renew o con el botón de Procesos. Una cuenta con membresía no vigente no puede enviar."
      cols={[{ k: "account_id", l: "Cuenta" }, { k: "status", l: "Estado" }, { k: "period_start", l: "Desde" }, { k: "period_end", l: "Vence" }, { k: "auto_renew", l: "Auto" }, { k: "renewals", l: "Renovaciones" }]}
      actions={[{ l: "Renovar ahora", body: r => r.status !== "cancelled" ? { renew: true, account: r.account_id } : null }, { l: "Cancelar", body: r => r.status !== "cancelled" ? { status: "cancelled" } : null }, { l: "Auto-renovación", body: r => ({ auto_renew: !r.auto_renew }) }]} /></>);
}
