"use client";
import { useParams } from "next/navigation";
import { Resource } from "../../Resource";
import { SCOPE_KEYS } from "@/lib/scopes";
export default function Banco() {
  const { id } = useParams<{ id: string }>(); const filter = { bank_id: id };
  return (<><h1>Entidad</h1>
    <Resource res="accounts" title="Cuentas" filter={filter} cols={[{ k: "iban", l: "IBAN" }, { k: "name", l: "Nombre" }, { k: "kind", l: "Tipo" }, { k: "status", l: "Estado" }, { k: "daily_limit", l: "Límite diario" }]}
      create={[{ k: "name", l: "Nombre" }, { k: "product_id", l: "Producto (opcional)", ref: "products", lab: ["code", "name"] }, { k: "kind", l: "Tipo (si no hay producto)", hint: "Junior: sin descubierto ni crédito, solo opera con Junior y cuentas del sistema; necesita ficha Junior y membresía.", t: "select", o: ["personal", "business", "shared", "junior", "system"] }]}
      actions={[{ l: "Límite diario…", prompt: "Límite diario en Pz", body: (r, v) => ({ daily_limit: Number(v) }) }, { l: "Vincular a cliente (DIP)…", prompt: "DIP del cliente", body: (r, v) => ({ dip: v }) }, { l: "Bloquear", body: r => r.status === "active" ? { status: "blocked" } : null }, { l: "Activar", body: r => r.status === "blocked" ? { status: "active" } : null }, { l: "Cerrar", body: r => r.status !== "closed" ? { status: "closed" } : null }]} />
    <Resource res="clients" title="Claves de API (conexión de apps)" filter={filter} cols={[{ k: "name", l: "Nombre" }, { k: "scopes", l: "Scopes" }, { k: "rate_limit", l: "Límite/min" }, { k: "active", l: "Activa" }]}
      create={[{ k: "name", l: "Nombre" }, { k: "scopes", l: "Permisos (scopes)", t: "multi", o: SCOPE_KEYS }, { k: "rate_limit", l: "Límite/min", t: "number" }]}
      actions={[{ l: "Permisos…", prompt: `Scopes separados por coma:\n${SCOPE_KEYS.join(", ")}`, body: (r, v) => ({ scopes: (v ?? "").split(",").map(x => x.trim()).filter(Boolean) }) }, { l: "Revocar", body: r => r.active ? { active: false } : null }, { l: "Reactivar", body: r => !r.active ? { active: true } : null }]} />
    <Resource res="webhooks" title="Webhooks" filter={filter} cols={[{ k: "url", l: "URL (https)" }, { k: "events", l: "Eventos" }, { k: "active", l: "Activo" }]}
      create={[{ k: "url", l: "URL https" }, { k: "events", l: "Eventos (coma, * = todos)", t: "list" }]}
      actions={[{ l: "Desactivar", body: r => r.active ? { active: false } : null }, { l: "Activar", body: r => !r.active ? { active: true } : null }]} />
    <Resource res="fees" title="Tarifas" filter={filter} cols={[{ k: "op_type", l: "Operación" }, { k: "method", l: "Método" }, { k: "rate", l: "Valor" }, { k: "min_amount", l: "Mín" }, { k: "max_amount", l: "Máx" }, { k: "payer", l: "Paga" }, { k: "valid_from", l: "Desde" }, { k: "valid_to", l: "Hasta" }]}
      create={[{ k: "method", l: "Método", t: "select", o: ["percent", "fixed"] }, { k: "rate", l: "Valor", t: "number" }, { k: "min_amount", l: "Mín", t: "number" }, { k: "max_amount", l: "Máx", t: "number" }, { k: "payer", l: "Quién paga", t: "select", o: ["user", "bank", "both", "exempt"] },
        { k: "beneficiary_account", l: "Cuenta destino", ref: "accounts", lab: ["iban", "name"] }, { k: "bank_pay_account", l: "Cuenta del banco", ref: "accounts", lab: ["iban", "name"] }, { k: "valid_from", l: "Desde", t: "date" }, { k: "valid_to", l: "Hasta", t: "date" }]}
      actions={[{ l: "Finalizar hoy", body: r => r.valid_to ? null : { valid_to: new Date().toISOString().slice(0, 10) } }]} />    <Resource res="policies" title="Normas de esta entidad (recargos, disputas, deuda)" filter={filter} cols={[{ k: "ref", l: "Ref" }, { k: "kind", l: "Clase" }, { k: "name", l: "Nombre" }, { k: "scope", l: "Ámbito" }, { k: "params", l: "Parámetros" }, { k: "status", l: "Estado" }]}
      create={[{ k: "kind", l: "Clase", t: "select", o: ["penalty", "dispute", "debt_terms"] }, { k: "name", l: "Nombre" }, { k: "type", l: "Recargo: tipo", t: "select", o: ["percent", "fixed"] }, { k: "value", l: "Recargo: valor", t: "number" }, { k: "grace_days", l: "Días de gracia", t: "number" }, { k: "max_days", l: "Disputa: días", t: "number" },
        { k: "max_principal", l: "Deuda: principal máx.", t: "number" }, { k: "interest_pct", l: "Deuda: interés %", t: "number" }, { k: "allow_partial", l: "Permite pagos parciales", t: "bool" }, { k: "dip", l: "Solo para un DIP (opcional)" }]}
      actions={[{ l: "Aprobar y publicar", body: r => r.status === "draft" ? { publish: true } : null }, { l: "Retirar", body: r => r.status === "published" ? { status: "retired" } : null }]} />
</>);
}
