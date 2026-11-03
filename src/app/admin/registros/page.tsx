"use client";
import { Resource } from "../Resource";
export default function Registros() {
  return (<><h1>Registros y control</h1>
    <Resource res="approvals" title="Aprobaciones" cols={[{ k: "ref", l: "Ref" }, { k: "subject", l: "Asunto" }, { k: "reason", l: "Motivo" }, { k: "result", l: "Resultado" }, { k: "at", l: "Fecha" }]}
      actions={[{ l: "Aprobar", body: r => !r.result ? { approve: true } : null }, { l: "Rechazar", body: r => !r.result ? { approve: false } : null }]} />
    <Resource res="incidents" title="Incidencias" cols={[{ k: "ref", l: "Ref" }, { k: "kind", l: "Tipo" }, { k: "status", l: "Estado" }, { k: "detail", l: "Detalle" }, { k: "at", l: "Fecha" }]}
      actions={[{ l: "Resolver", body: r => r.status === "open" ? { status: "resolved" } : null }]} />
    <Resource res="invoices" title="Facturas internas" cols={[{ k: "ref", l: "Ref" }, { k: "account_id", l: "Cuenta" }, { k: "concept", l: "Concepto" }, { k: "amount", l: "Pz" }, { k: "status", l: "Estado" }]}
      create={[{ k: "account_id", l: "Cuenta", ref: "accounts", lab: ["iban", "name"] }, { k: "concept", l: "Concepto" }, { k: "amount", l: "Importe", t: "number" }]} actions={[{ l: "Anular", body: r => r.status === "issued" ? { status: "void" } : null }]} />
    <Resource res="settlements" title="Liquidaciones bancarias" cols={[{ k: "ref", l: "Ref" }, { k: "period_from", l: "Desde" }, { k: "period_to", l: "Hasta" }, { k: "evaluated", l: "Evaluado" }, { k: "collected", l: "Cobrado" }, { k: "pending", l: "Pendiente" }, { k: "refunded", l: "Devuelto" }]}
      create={[{ k: "bank_id", l: "Entidad", ref: "banks", lab: ["code", "name"] }, { k: "period_from", l: "Desde", t: "date" }, { k: "period_to", l: "Hasta", t: "date" }]} />
    <Resource res="audit" title="Auditoría" cols={[{ k: "at", l: "Fecha" }, { k: "action", l: "Acción" }, { k: "entity", l: "Entidad" }, { k: "entity_id", l: "Id" }, { k: "actor", l: "Actor" }]} />
    <Resource res="numbering" title="Formatos de numeración activos" cols={[{ k: "kind", l: "Tipo" }, { k: "version", l: "v" }, { k: "prefix", l: "Prefijo" }, { k: "year_scoped", l: "Por año" }, { k: "width", l: "Dígitos" }, { k: "status", l: "Estado" }]} />
    <Resource res="outbox" title="Eventos de webhooks" cols={[{ k: "event", l: "Evento" }, { k: "status", l: "Estado" }, { k: "attempts", l: "Intentos" }, { k: "created_at", l: "Fecha" }]} /></>);
}
