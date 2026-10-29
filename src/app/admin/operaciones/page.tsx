"use client";
import { Resource } from "../Resource";
const A = { ref: "accounts", lab: ["iban", "name"] };
export default function Operaciones() {
  return (<><h1>Operaciones</h1>
    <Resource res="transactions" title="Movimientos y transferencias" cols={[{ k: "ref", l: "Operación" }, { k: "transfer_ref", l: "Transferencia" }, { k: "kind", l: "Tipo" }, { k: "status", l: "Estado" }, { k: "memo", l: "Concepto" }, { k: "created_at", l: "Fecha" }]}
      create={[{ k: "from_account", l: "Origen", ...A }, { k: "to_account", l: "Destino", ...A }, { k: "amount", l: "Importe Pz", t: "number" }, { k: "memo", l: "Concepto" }]}
      actions={[{ l: "Revertir", body: r => r.status === "posted" && r.kind !== "reversal" ? { reverse: true } : null }]} />
    <Resource res="scheduled" title="Programadas y recurrentes" cols={[{ k: "from_account", l: "Origen" }, { k: "to_account", l: "Destino" }, { k: "amount", l: "Pz" }, { k: "run_at", l: "Ejecución" }, { k: "recurrence", l: "Repite" }, { k: "status", l: "Estado" }]}
      create={[{ k: "from_account", l: "Origen", ...A }, { k: "to_account", l: "Destino", ...A }, { k: "amount", l: "Importe", t: "number" }, { k: "run_at", l: "Fecha y hora (2026-12-01T09:00:00Z)" }, { k: "recurrence", l: "Repetición (ej. 1 month)" }, { k: "memo", l: "Concepto" }]}
      actions={[{ l: "Cancelar", body: r => r.status === "active" ? { status: "cancelled" } : null }]} />
    <Resource res="batches" title="Nóminas y pagos por lotes" cols={[{ k: "kind", l: "Tipo" }, { k: "from_account", l: "Cuenta pagadora" }, { k: "status", l: "Estado" }, { k: "id", l: "Id" }]}
      create={[{ k: "kind", l: "Tipo", t: "select", o: ["payroll", "batch"] }, { k: "from_account", l: "Cuenta pagadora", ...A }]} actions={[{ l: "Ejecutar", body: r => r.status !== "done" ? { run: true } : null }]} />
    <Resource res="batchitems" title="Elementos de lote" cols={[{ k: "batch_id", l: "Lote" }, { k: "to_account", l: "Destino" }, { k: "amount", l: "Pz" }, { k: "status", l: "Estado" }, { k: "error", l: "Error" }]}
      create={[{ k: "batch_id", l: "Lote", ref: "batches", lab: ["kind", "status", "id"] }, { k: "to_account", l: "Destino", ...A }, { k: "amount", l: "Importe", t: "number" }]} /></>);
}
