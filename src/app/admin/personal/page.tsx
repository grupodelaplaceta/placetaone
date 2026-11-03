"use client";
import { Resource } from "../Resource";
const ROLES = ["admin", "financiero", "fiscal", "financiacion", "gestor_bancario", "auditor", "aprobador"];
export default function Personal() {
  return (<><h1>Personal</h1><p>Primero crea el usuario en Supabase → Authentication; luego dale rol aquí con su UUID. Solo administradores y aprobadores ven esta lista; solo administradores la modifican.</p>
    <Resource res="staff" title="Usuarios con acceso" cols={[{ k: "user_id", l: "UUID" }, { k: "role", l: "Rol" }, { k: "active", l: "Activo" }, { k: "bank_id", l: "Entidad (vacío = todas)" }]}
      create={[{ k: "user_id", l: "UUID del usuario" }, { k: "role", l: "Rol", t: "select", o: ROLES }, { k: "bank_id", l: "Limitar a entidad (uuid)" }]}
      actions={[{ l: "Desactivar", body: r => r.active ? { active: false } : null }, { l: "Activar", body: r => !r.active ? { active: true } : null }]} /></>);
}
