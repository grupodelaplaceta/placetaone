"use client";
import { Resource, Action } from "../Resource";
const to = (from: string[], status: string, l: string): Action => ({ l, body: r => (from.includes(String(r.status)) ? { status } : null) });
export default function Bancos() {
  return (<><h1>Bancos</h1><Resource res="banks" title="Entidades" cols={[{ k: "code", l: "Código" }, { k: "name", l: "Nombre" }, { k: "status", l: "Estado" }, { k: "description", l: "Descripción" }]}
    create={[{ k: "name", l: "Nombre" }, { k: "description", l: "Descripción" }]} href={r => `/admin/bancos/${r.id}`}
    actions={[to(["draft"], "review", "A revisión"), to(["review", "suspended"], "active", "Activar"), to(["review"], "draft", "A borrador"), to(["active"], "suspended", "Suspender"), to(["active", "suspended"], "closed", "Cerrar")]} /></>);
}
