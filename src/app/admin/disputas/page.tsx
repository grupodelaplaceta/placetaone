"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Reclamaciones de deudas (resolver: aprobador), plazos y umbrales configurables.
type Disputa = { id: string; debt_id: string; monto_reclamado: number; monto_devuelto: number; motivo: string; estado: string; aprobada_1: string | null; aprobada_2: string | null; plazo_resolucion: string };
type Param = { clave: string; valor: number; actualizado: string };
const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;
const ETIQUETAS: Record<string, string> = {
  "disputa.plazo_apertura_dias": "Días para reclamar desde el vencimiento (1-365)",
  "disputa.plazo_resolucion_dias": "Días para resolver desde la apertura (1-180)",
  "disputa.umbral_doble_aprobacion": "Devoluciones que requieren dos aprobadores, en Pz (0-1.000.000)",
};

export default function DisputasAdmin() {
  const [lista, setLista] = useState<Disputa[]>([]);
  const [params, setParams] = useState<Param[]>([]);
  const [msg, setMsg] = useState("");
  const [monto, setMonto] = useState<Record<string, string>>({});
  const [nuevo, setNuevo] = useState<Record<string, string>>({});
  const cargar = () => api("/api/admin/disputas").then((r: { disputas?: Disputa[]; parametros?: Param[] }) => { setLista(r.disputas ?? []); setParams(r.parametros ?? []); }).catch((e) => setMsg((e as Error).message));
  useEffect(() => { cargar(); }, []);
  const resolver = async (id: string, decision: string) => {
    try {
      const r = await api("/api/admin/disputas", "POST", { accion: "resolver", id, decision, monto: monto[id] || null });
      setMsg(r.resultado?.estado === "pendiente_segunda_aprobacion" ? "Primera aprobación registrada. Otra persona debe aprobar la devolución." : "Reclamación resuelta.");
      cargar();
    } catch (e) { setMsg((e as Error).message); }
  };
  const guardarParam = async (clave: string) => {
    try { await api("/api/admin/disputas", "POST", { accion: "parametro", clave, valor: Number(nuevo[clave]) }); setMsg("Parámetro guardado."); cargar(); }
    catch (e) { setMsg((e as Error).message); }
  };
  const vencida = (d: Disputa) => d.estado === "abierta" && new Date(d.plazo_resolucion) < new Date();
  return (
    <>
      <h1>Reclamaciones de deudas</h1>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      <Card titulo="Reclamaciones">
        <table style={{ width: "100%", fontSize: 14 }}>
          <thead><tr><th align="left">Motivo</th><th align="right">Reclamado</th><th align="left">Estado</th><th align="left">Plazo</th><th align="left">Resolver</th></tr></thead>
          <tbody>{lista.map((d) => (
            <tr key={d.id}>
              <td>{d.motivo}</td><td align="right">{d.monto_reclamado} Pz</td>
              <td><Badge tono={d.estado === "abierta" ? "neutral" : d.estado === "devuelta" ? "ok" : "bad"}>{d.estado}</Badge>{vencida(d) && <Badge tono="bad"> plazo vencido</Badge>}
                {d.aprobada_1 && d.estado === "abierta" && <Badge tono="neutral"> 1ª aprobación</Badge>}</td>
              <td>{d.plazo_resolucion}</td>
              <td>{d.estado === "abierta" && <>
                <input style={{ ...campo, width: 110 }} type="number" step="0.01" placeholder="Importe" value={monto[d.id] ?? ""} onChange={(e) => setMonto((x) => ({ ...x, [d.id]: e.target.value }))} />
                <button className="btn btn-primary" onClick={() => resolver(d.id, "devolucion")}>Devolver</button>{" "}
                <button className="btn" onClick={() => resolver(d.id, "rechazada")}>Rechazar</button></>}</td>
            </tr>))}</tbody>
        </table>
        <p className="muted">Las devoluciones salen de la cuenta del acreedor. Por encima del umbral, las aprueban dos personas distintas.</p>
      </Card>
      <Card titulo="Plazos y umbrales">
        {params.map((p) => (
          <div key={p.clave} style={{ marginBottom: 6 }}>
            <span style={{ display: "inline-block", minWidth: 380 }}>{ETIQUETAS[p.clave] ?? p.clave}: <strong>{p.valor}</strong></span>
            <input style={{ ...campo, width: 110 }} type="number" placeholder="Nuevo valor" value={nuevo[p.clave] ?? ""} onChange={(e) => setNuevo((x) => ({ ...x, [p.clave]: e.target.value }))} />
            <button className="btn" onClick={() => guardarParam(p.clave)}>Guardar</button>
          </div>))}
        <p className="muted">Los cambios se aplican a las reclamaciones nuevas. Las ya abiertas conservan su plazo.</p>
      </Card>
    </>
  );
}
