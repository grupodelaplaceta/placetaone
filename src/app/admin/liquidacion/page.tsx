"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Liquidación interbancaria: interruptores, límites, liquidación manual, tasas de operaciones y reversiones (doble aprobación).
type Banco = { id: string; code: string; name: string; nombre_visible?: string | null };
type Datos = { config: { liquidacion_activa: boolean; tasas_operaciones_activas: boolean } | null; liquidaciones: { id: string; fecha: string; banco_deudor: string; banco_acreedor: string; importe: number; estado: string; motivo: string | null }[];
  pendientes: { id: number; origen: string; destino: string; importe: number; fecha: string; ref: string }[]; limites: { bank_deudor: string; bank_acreedor: string; limite: number }[];
  reversiones: { id: string; liquidacion: string; motivo: string; solicitada_por: string; estado: string }[] };
const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;

export default function LiquidacionAdmin() {
  const [bancos, setBancos] = useState<Banco[]>([]);
  const [datos, setDatos] = useState<Datos | null>(null);
  const [msg, setMsg] = useState("");
  const [f, setF] = useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));
  const nombre = (id: string) => bancos.find((b) => b.id === id)?.code ?? id.slice(0, 8);

  const cargar = () => api("/api/admin/liquidacion").then((r: Datos) => setDatos(r)).catch((e) => setMsg((e as Error).message));
  useEffect(() => { api("/api/admin/pasarela").then((r: { bancos?: Banco[] }) => setBancos(r.bancos ?? [])).catch((e) => setMsg((e as Error).message)); cargar(); }, []);
  const accion = async (cuerpo: Record<string, unknown>, ok: string) => {
    try { await api("/api/admin/liquidacion", "POST", cuerpo); setMsg(ok); cargar(); } catch (e) { setMsg((e as Error).message); }
  };

  return (
    <>
      <h1>Liquidación interbancaria</h1>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      {datos && (
        <>
          <Card titulo="Interruptores (todo empieza apagado)">
            <label style={{ display: "block", marginBottom: 6 }}>
              <input type="checkbox" checked={!!datos.config?.liquidacion_activa} onChange={(e) => accion({ accion: "config", liquidacion: e.target.checked, tasas: !!datos.config?.tasas_operaciones_activas }, "Interruptor de liquidación actualizado.")} /> Liquidación activa
            </label>
            <label style={{ display: "block", marginBottom: 6 }}>
              <input type="checkbox" checked={!!datos.config?.tasas_operaciones_activas} onChange={(e) => accion({ accion: "config", liquidacion: !!datos.config?.liquidacion_activa, tasas: e.target.checked }, "Interruptor de tasas actualizado.")} /> Tasas en transferencias y cargos de empresa activas
            </label>
            <p className="muted">Activar cualquiera de los dos cambia dinero real. Actívalos solo después de probar la instalación en una base de pruebas.</p>
          </Card>

          <Card titulo="Liquidar">
            <input style={campo} type="date" value={f.fecha ?? ""} onChange={(e) => set("fecha", e.target.value)} />
            <button className="btn btn-primary" onClick={() => accion({ accion: "liquidar", fecha: f.fecha || undefined }, "Liquidación ejecutada.")}>Liquidar</button>
            <p className="muted">Pendientes sin liquidar: {datos.pendientes.length}. La liquidación es todo o nada: si un banco no tiene saldo, no se ejecuta ninguna.</p>
          </Card>

          <Card titulo="Límites de exposición">
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">Deudor</th><th align="left">Acreedor</th><th align="right">Límite</th></tr></thead>
              <tbody>{datos.limites.map((l, i) => <tr key={i}><td>{nombre(l.bank_deudor)}</td><td>{nombre(l.bank_acreedor)}</td><td align="right">{l.limite} Pz</td></tr>)}</tbody>
            </table>
            <input style={campo} placeholder="Banco deudor (id)" value={f.deudor ?? ""} onChange={(e) => set("deudor", e.target.value)} />
            <input style={campo} placeholder="Banco acreedor (id)" value={f.acreedor ?? ""} onChange={(e) => set("acreedor", e.target.value)} />
            <input style={campo} type="number" placeholder="Límite (Pz)" value={f.limite ?? ""} onChange={(e) => set("limite", e.target.value)} />
            <button className="btn" onClick={() => accion({ accion: "limite", deudor: f.deudor, acreedor: f.acreedor, limite: Number(f.limite ?? 0) }, "Límite guardado.")}>Guardar límite</button>
          </Card>

          <Card titulo="Liquidaciones">
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">Fecha</th><th align="left">Deudor → acreedor</th><th align="right">Importe</th><th align="left">Estado</th><th align="left">Motivo</th><th /></tr></thead>
              <tbody>{datos.liquidaciones.map((l) => (
                <tr key={l.id}><td>{l.fecha}</td><td>{nombre(l.banco_deudor)} → {nombre(l.banco_acreedor)}</td><td align="right">{l.importe} Pz</td>
                  <td><Badge tono={l.estado === "ejecutada" ? "ok" : "neutral"}>{l.estado}</Badge></td><td>{l.motivo ?? "—"}</td>
                  <td>{l.estado === "ejecutada" && <button className="btn" onClick={() => accion({ accion: "solicitar_reversion", liquidacion: l.id, motivo: f.motivo ?? "" }, "Reversión solicitada. Otra persona debe aprobarla.")}>Pedir reversión</button>}</td></tr>))}</tbody>
            </table>
            <input style={{ ...campo, minWidth: 320 }} placeholder="Motivo de la reversión (mín. 10 caracteres)" value={f.motivo ?? ""} onChange={(e) => set("motivo", e.target.value)} />
          </Card>

          <Card titulo="Reversiones pendientes de aprobación">
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">Motivo</th><th align="left">Estado</th><th /></tr></thead>
              <tbody>{datos.reversiones.map((r) => (
                <tr key={r.id}><td>{r.motivo}</td><td><Badge tono="neutral">{r.estado}</Badge></td>
                  <td><button className="btn btn-primary" onClick={() => accion({ accion: "aprobar_reversion", reversion: r.id }, "Reversión aprobada y ejecutada.")}>Aprobar</button></td></tr>))}</tbody>
            </table>
            <p className="muted">Quien pidió la reversión no puede aprobarla: el sistema lo rechaza.</p>
          </Card>

          <Card titulo="Tasas de transferencias y cargos de empresa (tarifa propietaria)">
            <select style={campo} value={f.banco ?? ""} onChange={(e) => set("banco", e.target.value)}>
              <option value="">Elige entidad…</option>{bancos.map((b) => <option key={b.id} value={b.id}>{b.nombre_visible ?? b.name}</option>)}
            </select>
            <select style={campo} value={f.operacion ?? "transferencia_interbancaria"} onChange={(e) => set("operacion", e.target.value)}>
              <option value="transferencia_interbancaria">Transferencia interbancaria</option><option value="cargo_tarjeta_empresa">Cargo de tarjeta de empresa</option>
            </select>
            <select style={campo} value={f.tipo ?? "porcentaje"} onChange={(e) => set("tipo", e.target.value)}><option value="porcentaje">Porcentaje</option><option value="fijo">Importe fijo</option></select>
            <input style={{ ...campo, width: 110 }} type="number" step="0.01" placeholder="Valor" value={f.valor ?? ""} onChange={(e) => set("valor", e.target.value)} />
            <select style={campo} value={f.beneficiario ?? "propietario"} onChange={(e) => set("beneficiario", e.target.value)}><option value="propietario">Cobra el propietario</option><option value="banco">Cobra el banco emisor</option></select>
            <button className="btn btn-primary" onClick={() => accion({ accion: "tasa_operacion", bank_id: f.banco, operacion: f.operacion ?? "transferencia_interbancaria", tipo: f.tipo ?? "porcentaje", valor: Number(f.valor ?? 0), beneficiario: f.beneficiario ?? "propietario" }, "Tasa creada.")}>Crear tasa</button>
            <p className="muted">La paga siempre el banco emisor. Las operaciones dentro de la misma entidad no pagan tasa.</p>
          </Card>
        </>
      )}
    </>
  );
}
