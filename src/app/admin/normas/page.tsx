"use client";
import { Resource, Field } from "../Resource";
const who: Field[] = [{ k: "bank_id", l: "Solo esta entidad", ref: "banks", lab: ["code", "name"] }, { k: "customer_id", l: "Solo este cliente", ref: "customers", lab: ["dip", "full_name"] }, { k: "dip", l: "O vincular a un DIP" }, { k: "valid_from", l: "Desde", t: "date" }, { k: "valid_to", l: "Hasta", t: "date" }, { k: "reason", l: "Motivo" }];
const cols: Field[] = [{ k: "ref", l: "Ref" }, { k: "name", l: "Nombre" }, { k: "scope", l: "Ámbito" }, { k: "dip", l: "DIP" }, { k: "params", l: "Parámetros" }, { k: "valid_from", l: "Desde" }, { k: "valid_to", l: "Hasta" }, { k: "status", l: "Estado" }];
const actions = [{ l: "Aprobar y publicar", body: (r: Record<string, unknown>) => r.status === "draft" ? { publish: true } : null }, { l: "Retirar", body: (r: Record<string, unknown>) => r.status === "published" ? { status: "retired" } : null }];
export default function Normas() {
  return (<><h1>Normas</h1><p>Sin destinatario = norma global. Con entidad, cliente o DIP gana la más específica; si dos normas empatan en el mismo nivel no se aplica ninguna y se abre una incidencia. Los topes centrales se fijan en Configuración.</p>
    <Resource res="policies" title="Recargos por mora" filter={{ kind: "penalty" }} cols={cols} actions={actions}
      create={[{ k: "name", l: "Nombre" }, { k: "type", l: "Tipo", t: "select", o: ["percent", "fixed"] }, { k: "value", l: "Valor (% o Pz)", t: "number" }, { k: "grace_days", l: "Días de gracia", t: "number" }, { k: "max_amount", l: "Máximo Pz", t: "number" }, ...who]} />
    <Resource res="policies" title="Disputas" filter={{ kind: "dispute" }} cols={cols} actions={actions}
      create={[{ k: "name", l: "Nombre" }, { k: "max_days", l: "Días para resolver", t: "number" }, { k: "freeze_collection", l: "Congelar cobro", t: "bool" }, { k: "requires_approval", l: "Exige aprobación", t: "bool" }, ...who]} />
    <Resource res="policies" title="Condiciones de deuda" filter={{ kind: "debt_terms" }} cols={cols} actions={actions}
      create={[{ k: "name", l: "Nombre" }, { k: "max_principal", l: "Principal máximo Pz", t: "number" }, { k: "interest_pct", l: "Interés mensual %", t: "number" }, { k: "allow_partial", l: "Permite pagos parciales", t: "bool" }, ...who]} /></>);
}
