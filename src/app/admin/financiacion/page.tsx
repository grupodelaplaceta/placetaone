"use client";
import { Resource } from "../Resource";
const A = { ref: "accounts", lab: ["iban", "name"] };
export default function Financiacion() {
  return (<><h1>Subvenciones, bonos y tesorería</h1>
    <details open style={{ background: "#f8fafc", border: "1px solid #cbd5e1", borderRadius: 10, padding: 16, marginBottom: 16 }}>
      <summary style={{ fontWeight: 700, cursor: "pointer" }}>Cómo funcionan las subvenciones y los bonos (leer antes de dar de alta nada)</summary>
      <p><strong>Dónde se dan de alta.</strong> Todo se gestiona en esta pantalla, en este orden: Programas, Concesiones y Justificaciones. Las tres tablas están abajo.</p>
      <ol>
        <li><strong>Programa.</strong> Es el marco de la ayuda: nombre, tipo (subvención o bono), presupuesto y cuenta de fondos. La cuenta de fondos es la cuenta de la que sale el dinero al pagar. El tipo sirve para clasificar el programa.</li>
        <li><strong>Concesión.</strong> Asigna un importe máximo a un beneficiario (una cuenta) dentro de un programa. Es el tope de lo que el beneficiario puede cobrar.</li>
        <li><strong>Justificación.</strong> El beneficiario presenta un gasto ya hecho: la transacción de su cuenta, el número de factura y el importe. El sistema no deja que la suma de justificaciones supere lo concedido. Las justificaciones pueden quedar pendientes, aprobadas, pagadas o rechazadas.</li>
        <li><strong>Aprobar y pagar.</strong> Es el único paso que mueve dinero. Transfiere desde la cuenta de fondos al beneficiario el importe justificado, suma al «aprobado» y al «pagado» de la concesión y asigna una referencia de reembolso. No se puede pagar dos veces la misma justificación.</li>
      </ol>
      <p><strong>Lo que hoy no está limitado.</strong> Una subvención se paga contra gastos justificados, pero el sistema no comprueba el tipo de gasto ni el comercio de la justificación. Tampoco limita en qué se gasta el dinero una vez pagado. Los bonos RBU tampoco tienen esa restricción.</p>
      <p><strong>Bonos RBU.</strong> El bono semanal sale de la cuenta que se configura en <a href="/admin/destinos">Destinos</a> (si no se configura, sale de la Reserva). El usuario lo reclama en su tarjeta prepago, y los importes caducan si no se usan.</p>
      <p><strong>Quién puede hacer cada cosa.</strong> Programas y concesiones: personal de financiación. Justificaciones y pagos: personal de financiación y financiero.</p>
    </details>
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
      actions={[{ l: "Abrir disputa…", prompt: "Motivo de la disputa", body: (r, v) => !r.disputed ? { dispute: v } : null }]} /></>);
}
