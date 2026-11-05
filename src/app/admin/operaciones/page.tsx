"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Pagos de la pasarela, operaciones interbancarias, restricciones de pago y tarifa de comisiones de una entidad.
type Banco = { id: string; code: string; name: string; nombre_visible?: string | null };
const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;
const RESTRICCIONES: [string, string, string][] = [
  ["medio", "cuenta", "Pagos desde cuenta"], ["medio", "tarjeta", "Pagos con tarjeta"],
  ["tarjeta", "digital", "Tarjeta digital"], ["tarjeta", "physical", "Tarjeta física"], ["tarjeta", "credit", "Tarjeta de crédito"], ["tarjeta", "prepago", "Tarjeta prepago"],
  ["modalidad", "inmediata", "Pagos inmediatos"], ["modalidad", "diferida", "Pagos diferidos"], ["operacion", "interbancario", "Pagos interbancarios"],
];

export default function OperacionesAdmin() {
  const [bancos, setBancos] = useState<Banco[]>([]);
  const [bank, setBank] = useState("");
  const [vista, setVista] = useState<"pagos" | "interbancarias" | "reglas">("pagos");
  const [datos, setDatos] = useState<Record<string, unknown>>({});
  const [msg, setMsg] = useState("");
  const [f, setF] = useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));

  useEffect(() => { api("/api/admin/pasarela").then((r: { bancos?: Banco[] }) => setBancos(r.bancos ?? [])).catch((e) => setMsg((e as Error).message)); }, []);
  const cargar = (b: string, v: string) => {
    if (!b) return;
    api(`/api/admin/operaciones?bank_id=${encodeURIComponent(b)}&vista=${v}`).then((r: Record<string, unknown>) => setDatos(r)).catch((e) => setMsg((e as Error).message));
  };
  useEffect(() => { setDatos({}); cargar(bank, vista); }, [bank, vista]);

  const accion = async (cuerpo: Record<string, unknown>, ok: string) => {
    try { await api("/api/admin/operaciones", "POST", { bank_id: bank, ...cuerpo }); setMsg(ok); cargar(bank, vista); }
    catch (e) { setMsg((e as Error).message); }
  };

  const restr = (datos.restricciones as { tipo: string; valor: string; bloqueado: boolean }[] | undefined) ?? [];
  const bloqueada = (t: string, v: string) => restr.some((r) => r.tipo === t && r.valor === v && r.bloqueado);
  const pagos = (datos.pagos as Record<string, unknown>[] | undefined) ?? [];
  const interb = (datos.operaciones as Record<string, unknown>[] | undefined) ?? [];

  return (
    <>
      <h1>Pagos y reglas</h1>
      <div style={{ marginBottom: 10 }}>
        <select style={{ ...campo, minWidth: 320 }} value={bank} onChange={(e) => setBank(e.target.value)}>
          <option value="">Elige una entidad…</option>
          {bancos.map((b) => <option key={b.id} value={b.id}>{b.nombre_visible ?? b.name} ({b.code})</option>)}
        </select>
        {(["pagos", "interbancarias", "reglas"] as const).map((v) => (
          <button key={v} className={vista === v ? "btn btn-primary" : "btn"} style={{ marginLeft: 6 }} onClick={() => setVista(v)}>
            {v === "pagos" ? "Pagos" : v === "interbancarias" ? "Interbancarias" : "Reglas y comisiones"}
          </button>
        ))}
      </div>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      {!bank && <p className="muted">Elige una entidad.</p>}

      {bank && vista === "pagos" && (
        <Card titulo="Últimos 100 pagos de la pasarela">
          <table style={{ width: "100%", fontSize: 14 }}>
            <thead><tr><th align="left">Referencia</th><th align="left">Estado</th><th align="right">Importe</th><th align="right">Comisión</th><th align="left">Medio</th><th align="left">Interbancario</th><th align="left">Creado</th></tr></thead>
            <tbody>{pagos.map((p) => (
              <tr key={String(p.id)}>
                <td className="mono">{String(p.client_ref)}</td><td>{String(p.estado)}</td><td align="right">{Number(p.importe).toFixed(2)} Pz</td>
                <td align="right">{Number(p.comision).toFixed(2)} Pz</td><td>{String(p.medio)}</td><td>{p.interbancaria ? "sí" : "no"}</td>
                <td>{new Date(String(p.creada)).toLocaleString("es-ES")}</td>
              </tr>))}</tbody>
          </table>
        </Card>
      )}

      {bank && vista === "interbancarias" && (
        <Card titulo="Operaciones interbancarias">
          <p className="muted">Hace 30 días por defecto. Cambia las fechas en la API si necesitas otro periodo.</p>
          <table style={{ width: "100%", fontSize: 14 }}>
            <thead><tr><th align="left">Referencia</th><th align="left">Sentido</th><th align="left">Banco destino</th><th align="left">Estado</th><th align="right">Importe</th><th align="right">Comisión</th></tr></thead>
            <tbody>{interb.map((o) => (
              <tr key={String(o.id)}>
                <td className="mono">{String(o.referencia)}</td><td>{String(o.sentido)}</td><td>{String(o.banco_destino ?? "—")}</td>
                <td>{String(o.estado)}</td><td align="right">{Number(o.importe).toFixed(2)} Pz</td><td align="right">{Number(o.comision ?? 0).toFixed(2)} Pz</td>
              </tr>))}</tbody>
          </table>
        </Card>
      )}

      {bank && vista === "reglas" && (
        <>
          <Card titulo="Qué puede pagar esta entidad (restricciones)">
            {RESTRICCIONES.map(([t, v, etiqueta]) => (
              <label key={`${t}:${v}`} style={{ display: "block", marginBottom: 6 }}>
                <input type="checkbox" checked={!bloqueada(t, v)} onChange={(e) => accion({ accion: "restriccion", tipo: t, valor: v, bloqueado: !e.target.checked }, `${etiqueta}: ${e.target.checked ? "permitido" : "prohibido"}.`)} />
                {" "}{etiqueta} {bloqueada(t, v) && <Badge tono="bad">prohibido</Badge>}
              </label>
            ))}
          </Card>
          <Card titulo="Tarifa de comisiones interbancarias (tarifa propietaria)">
            <p>Actual: {datos.comision ? JSON.stringify(datos.comision) : "sin tarifa (sin comisión)"}</p>
            <select style={campo} value={f.tipo ?? "porcentaje"} onChange={(e) => set("tipo", e.target.value)}><option value="porcentaje">Porcentaje</option><option value="fijo">Importe fijo</option></select>
            <input style={{ ...campo, width: 120 }} type="number" step="0.01" placeholder="Valor" value={f.valor ?? ""} onChange={(e) => set("valor", e.target.value)} />
            <select style={campo} value={f.beneficiario ?? "propietario"} onChange={(e) => set("beneficiario", e.target.value)}><option value="propietario">Cobra el propietario</option><option value="banco_pagador">Cobra el banco del pagador</option></select>
            <button className="btn btn-primary" onClick={() => accion({ accion: "comision", tipo: f.tipo ?? "porcentaje", valor: Number(f.valor ?? 0), beneficiario: f.beneficiario ?? "propietario" }, "Tarifa guardada.")}>Guardar tarifa</button>
            <p className="muted">Quién paga la comisión (cliente o banco) lo decide cada banco en su API.</p>
          </Card>
        </>
      )}
    </>
  );
}
