"use client";
import { Resource } from "../Resource";
const res = (l: string, o: string) => ({ l, prompt: "Nota de resolución", body: (r: Record<string, unknown>, v?: string) => r.status === "open" ? { resolve: o, note: v } : null });
export default function Disputas() {
  return (<><h1>Disputas</h1><p>Se abren desde Fiscalidad (recibos) o Financiación (deuda). Mientras están abiertas no se cobra ni se penaliza. La resuelve una persona distinta de quien la abrió.</p>
    <Resource res="disputes" title="Disputas" cols={[{ k: "ref", l: "Ref" }, { k: "subject_type", l: "Objeto" }, { k: "reason", l: "Motivo" }, { k: "status", l: "Estado" }, { k: "due_at", l: "Plazo" }, { k: "resolution", l: "Resolución" }]}
      actions={[res("Estimar (anula)", "upheld"), res("Desestimar", "rejected"), res("Retirar", "withdrawn")]} /></>);
}
