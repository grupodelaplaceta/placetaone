"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { Resource } from "../Resource";
export default function Fiscal() {
  const [rules, setRules] = useState<{ id: string; code: string; name: string }[]>([]); const [sel, setSel] = useState("");
  useEffect(() => { api("/api/admin/r/taxrules").then(setRules).catch(() => {}); }, []);
  return (<><h1>Fiscalidad interna</h1>
    <Resource res="taxrules" title="Impuestos / normas" cols={[{ k: "code", l: "Código" }, { k: "name", l: "Nombre" }, { k: "max_rate", l: "Límite central %" }, { k: "collector_account", l: "Cuenta recaudadora" }]}
      create={[{ k: "code", l: "Código (IVA, IRM…)" }, { k: "name", l: "Nombre" }, { k: "max_rate", l: "Límite central %", t: "number" }, { k: "collector_account", l: "Cuenta recaudadora", ref: "accounts", lab: ["iban", "name"] }]} />
    <p><label>Versiones de: <select value={sel} onChange={e => setSel(e.target.value)}><option value="">— elige norma —</option>{rules.map(r => <option key={r.id} value={r.id}>{r.code} · {r.name}</option>)}</select></label></p>
    {sel && <Resource key={sel} res="taxversions" title="Versiones" filter={{ rule_id: sel }} cols={[{ k: "version", l: "v" }, { k: "method", l: "Método" }, { k: "rate", l: "Tipo" }, { k: "valid_from", l: "Desde" }, { k: "valid_to", l: "Hasta" }, { k: "status", l: "Estado" }, { k: "retro_mode", l: "Retroactivo" }, { k: "reason", l: "Motivo" }]}
      create={[{ k: "method", l: "Método", t: "select", o: ["percent", "fixed", "brackets"] }, { k: "rate", l: "Tipo / importe", t: "number" }, { k: "min_amount", l: "Mínimo", t: "number" }, { k: "max_amount", l: "Máximo", t: "number" }, { k: "valid_from", l: "Entra en vigor", t: "date" }, { k: "valid_to", l: "Fin", t: "date" },
        { k: "retro_mode", l: "Retroactivo", t: "select", o: ["prohibited", "simulation", "automatic"] }, { k: "reason", l: "Motivo" }, { k: "scope_bank", l: "Solo entidad (uuid, opcional)" }]}
      actions={[{ l: "Publicar", body: r => r.status === "draft" ? { publish: true } : null }]} />}
    <Resource res="brackets" title="Tramos (para versiones de método «brackets»)" cols={[{ k: "version_id", l: "Versión" }, { k: "from_amount", l: "Desde" }, { k: "to_amount", l: "Hasta" }, { k: "rate", l: "Tipo %" }]}
      create={[{ k: "version_id", l: "Versión (borrador)", ref: "taxversions", lab: ["version", "method", "status", "id"] }, { k: "from_amount", l: "Desde", t: "number" }, { k: "to_amount", l: "Hasta (vacío = sin tope)", t: "number" }, { k: "rate", l: "Tipo %", t: "number" }]} />    <Resource res="receipts" title="Recibos fiscales" cols={[{ k: "ref", l: "Ref" }, { k: "account_id", l: "Cuenta" }, { k: "amount", l: "Importe" }, { k: "paid_amount", l: "Pagado" }, { k: "status", l: "Estado" }, { k: "due_date", l: "Vence" }, { k: "disputed", l: "Disputa" }]}
      actions={[{ l: "Cobrar", body: r => r.status === "issued" ? { pay: true } : null }, { l: "Abrir disputa…", prompt: "Motivo de la disputa", body: (r, v) => !r.disputed ? { dispute: v } : null }]} />
    <Resource res="exemptions" title="Exenciones" cols={[{ k: "rule_id", l: "Norma" }, { k: "account_id", l: "Cuenta" }, { k: "valid_from", l: "Desde" }, { k: "valid_to", l: "Hasta" }, { k: "reason", l: "Motivo" }, { k: "legal_basis", l: "Fundamento" }]}
      create={[{ k: "rule_id", l: "Norma", ref: "taxrules", lab: ["code"] }, { k: "account_id", l: "Cuenta", ref: "accounts", lab: ["iban", "name"] }, { k: "valid_from", l: "Desde", t: "date" }, { k: "valid_to", l: "Hasta", t: "date" }, { k: "reason", l: "Motivo" }, { k: "legal_basis", l: "Fundamento normativo" }]} />
    <Resource res="distribution" title="Distribución de lo recaudado" cols={[{ k: "rule_id", l: "Norma" }, { k: "account_id", l: "Cuenta destino" }, { k: "pct", l: "%" }]}
      create={[{ k: "rule_id", l: "Norma", ref: "taxrules", lab: ["code"] }, { k: "account_id", l: "Cuenta destino", ref: "accounts", lab: ["iban", "name"] }, { k: "pct", l: "Porcentaje", t: "number" }]} />
</>);
}
