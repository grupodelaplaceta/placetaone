"use client";
import { Resource } from "../Resource";
const A = { ref: "accounts", lab: ["iban", "name"] };
export default function Financiacion() {
  return (<><h1>Subvenciones, bonos y tesorería</h1>
    <Resource res="grantprograms" title="Programas" cols={[{ k: "name", l: "Nombre" }, { k: "kind", l: "Tipo" }, { k: "budget", l: "Presupuesto" }, { k: "funding_account", l: "Cuenta de fondos" }]}
      create={[{ k: "name", l: "Nombre" }, { k: "kind", l: "Tipo", t: "select", o: ["subvencion", "bono"] }, { k: "budget", l: "Presupuesto", t: "number" }, { k: "funding_account", l: "Cuenta de fondos", ...A }]} />
    <Resource res="grants" title="Concesiones" cols={[{ k: "ref", l: "Ref" }, { k: "beneficiary_account", l: "Beneficiario" }, { k: "granted", l: "Concedido" }, { k: "approved", l: "Aprobado" }, { k: "paid", l: "Pagado" }]}
      create={[{ k: "program_id", l: "Programa", ref: "grantprograms", lab: ["name", "kind"] }, { k: "beneficiary_account", l: "Beneficiario", ...A }, { k: "granted", l: "Importe concedido", t: "number" }]} />
    <Resource res="justifications" title="Justificaciones y reembolsos" cols={[{ k: "ref", l: "Ref" }, { k: "invoice_ref", l: "Factura" }, { k: "amount", l: "Pz" }, { k: "status", l: "Estado" }, { k: "reimb_ref", l: "Reembolso" }]}
      create={[{ k: "grant_id", l: "Concesión", ref: "grants", lab: ["ref", "granted"] }, { k: "transaction_id", l: "Transacción", ref: "transactions", lab: ["ref", "memo"] }, { k: "invoice_ref", l: "Nº factura" }, { k: "amount", l: "Importe", t: "number" }]}
      actions={[{ l: "Aprobar y pagar", body: r => r.status === "pending" || r.status === "approved" ? { reimburse: true } : null }, { l: "Rechazar", body: r => r.status === "pending" ? { status: "rejected" } : null }]} />
    <Resource res="budgets" title="Presupuestos y fondos restringidos" cols={[{ k: "name", l: "Nombre" }, { k: "period", l: "Periodo" }, { k: "approved", l: "Aprobado" }, { k: "committed", l: "Comprometido" }, { k: "executed", l: "Ejecutado" }, { k: "restricted", l: "Restringido" }]}
      create={[{ k: "name", l: "Nombre" }, { k: "period", l: "Periodo ([2026-01-01,2026-12-31])" }, { k: "approved", l: "Aprobado", t: "number" }, { k: "restricted", l: "Fondo restringido", t: "bool" }]} />
    <Resource res="debts" title="Deuda interna autorizada" cols={[{ k: "ref", l: "Ref" }, { k: "account_id", l: "Deudor" }, { k: "principal", l: "Principal" }, { k: "paid", l: "Pagado" }, { k: "due_date", l: "Vence" }, { k: "disputed", l: "Disputa" }]}
      create={[{ k: "account_id", l: "Deudor", ...A }, { k: "creditor_account", l: "Acreedor", ...A }, { k: "principal", l: "Principal", t: "number" }, { k: "due_date", l: "Vencimiento", t: "date" }, { k: "reason", l: "Origen autorizado" }]}
      actions={[{ l: "Marcar disputa", body: r => !r.disputed ? { disputed: true } : null }, { l: "Quitar disputa", body: r => r.disputed ? { disputed: false } : null }]} /></>);
}
