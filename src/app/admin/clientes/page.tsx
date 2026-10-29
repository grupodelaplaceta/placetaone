"use client";
import { Resource } from "../Resource";
export default function Clientes() {
  return (<><h1>Clientes</h1><p>Cada cliente tiene un DIP único. Las normas (recargos, disputas, deuda) pueden asignarse a un cliente concreto o a su DIP. Para vincular una cuenta: Bancos → Gestionar → «Vincular a cliente (DIP)…».</p>
    <Resource res="customers" title="Clientes registrados" cols={[{ k: "dip", l: "DIP" }, { k: "full_name", l: "Nombre" }, { k: "bank_id", l: "Entidad" }, { k: "user_id", l: "Usuario (UUID)" }, { k: "status", l: "Estado" }]}
      create={[{ k: "dip", l: "DIP (A-Z, 0-9, -)" }, { k: "full_name", l: "Nombre completo" }, { k: "bank_id", l: "Entidad", ref: "banks", lab: ["code", "name"] }, { k: "user_id", l: "UUID de usuario (opcional)" }]}
      actions={[{ l: "Bloquear", body: r => r.status === "active" ? { status: "blocked" } : null }, { l: "Activar", body: r => r.status === "blocked" ? { status: "active" } : null }]} />    <Resource res="juniorprofiles" title="Ficha Junior (control parental)" help="Las cuentas Junior de este cliente heredan estos límites. Si está bloqueada o supera un límite, la operación se rechaza."
      cols={[{ k: "customer_id", l: "Cliente" }, { k: "birth_date", l: "Nacimiento" }, { k: "guardian_user", l: "Tutor (UUID)" }, { k: "per_tx_limit", l: "Por operación" }, { k: "daily_limit", l: "Diario" }, { k: "monthly_limit", l: "Mensual" }, { k: "card_enabled", l: "Tarjeta" }, { k: "locked", l: "Bloqueada" }]}
      create={[{ k: "customer_id", l: "Cliente", ref: "customers", lab: ["dip", "full_name"] }, { k: "birth_date", l: "Nacimiento", t: "date" }, { k: "guardian_user", l: "UUID del tutor" }, { k: "per_tx_limit", l: "Límite por operación", t: "number" }, { k: "daily_limit", l: "Límite diario", t: "number" }, { k: "monthly_limit", l: "Límite mensual", t: "number" }, { k: "card_enabled", l: "Permite tarjeta", t: "bool" }]}
      actions={[{ l: "Bloquear", body: r => !r.locked ? { locked: true } : null }, { l: "Desbloquear", body: r => r.locked ? { locked: false } : null }, { l: "Límite diario…", prompt: "Nuevo límite diario (Pz)", body: (r, v) => ({ daily_limit: Number(v) }) }]} /></>);
}
