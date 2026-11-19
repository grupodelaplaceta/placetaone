"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { dlg } from "../ui";

// Dónde va cada impuesto, qué cuenta sirve la RBU, qué cuentas institucionales operan con Junior y quién paga por Capitalia.
type D = any;
const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
const th = { textAlign: "left", padding: "6px 8px", borderBottom: "1px solid #ddd", fontSize: 13 } as const;
const td = { padding: "6px 8px", borderBottom: "1px solid #eee", fontSize: 13, verticalAlign: "middle" } as const;

export default function Destinos() {
  const [d, setD] = useState<D | null>(null); const [msg, setMsg] = useState("");
  const [nuevos, setNuevos] = useState<Record<string, string>>({}); const [cuentaNueva, setCuentaNueva] = useState(""); const [junior, setJunior] = useState(false);
  const [bancoCap, setBancoCap] = useState("");
  const cargar = () => api("/api/admin/infra").then(setD).catch((e) => setMsg(e.message));
  useEffect(() => { cargar(); }, []);

  const ejecutar = async (fn: string, body: object, ok: string) => {
    try { await api(`/api/rpc/${fn}`, "POST", body); setMsg(ok); cargar(); } catch (e) { setMsg((e as Error).message); }
  };
  const cambiarDestino = async (codigo: string) => {
    const cuenta = nuevos[codigo]; if (!cuenta) return;
    if (!(await dlg.confirm(`Cambiar el destino de ${codigo}. Afecta a los cobros a partir de ahora. ¿Continuar?`))) return;
    ejecutar("plone27_tax_set_destination", { p_code: codigo, p_account: cuenta }, `Destino de ${codigo} actualizado.`);
  };
  const cambiarConfig = async (clave: string, cuenta: string) => {
    if (!cuenta || !(await dlg.confirm(`Cambiar la cuenta de ${clave === "cuenta_tributos" ? "Tributos" : "origen de la RBU"}. ¿Continuar?`))) return;
    ejecutar("plone27_config_set", { p_key: clave, p_account: cuenta }, "Configuración actualizada.");
  };
  const marcarJunior = async (cuenta: string, motivoPrevio: string, marcar: boolean) => {
    const motivo = motivoPrevio && motivoPrevio.length >= 10 ? motivoPrevio : await dlg.prompt("Motivo (mín. 10 caracteres)");
    if (!motivo) return;
    ejecutar("plone27_institutional_set", { p_account: cuenta, p_motivo: motivo, p_junior: marcar }, "Cuenta institucional actualizada.");
  };
  const añadirInstitucional = async () => {
    if (!cuentaNueva) return;
    const motivo = await dlg.prompt("Motivo para declararla institucional (mín. 10 caracteres)");
    if (!motivo) return;
    ejecutar("plone27_institutional_set", { p_account: cuentaNueva, p_motivo: motivo, p_junior: junior }, "Cuenta institucional registrada.");
  };

  if (!d) return <><h1>Destinos y cuentas institucionales</h1>{msg && <p role="alert" style={{ color: "#a33" }}>{msg}</p>}</>;
  const opcionesInst = d.institucionales.lista.map((i: any) => ({ id: i.cuenta, etiqueta: i.etiqueta }));
  const selectInst = (valor: string, onChange: (v: string) => void) => (
    <select value={valor} onChange={(e) => onChange(e.target.value)}><option value="">— elige cuenta institucional —</option>
      {opcionesInst.map((o: any) => <option key={o.id} value={o.id}>{o.etiqueta}</option>)}</select>);

  return (<>
    <h1>Destinos y cuentas institucionales</h1>
    {msg && <p role="status" style={{ color: "#345" }}>{msg}</p>}
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Destino de cada impuesto</h2>
      <p>Cada impuesto ingresa lo que recauda en una cuenta institucional con IBAN. Solo se pueden elegir cuentas institucionales. Los impuestos suelen ir a Tributos. Las cotizaciones van a la Reserva (Art. 4.5).</p>
      <table style={{ width: "100%", borderCollapse: "collapse" }}><thead><tr>{["Impuesto", "Destino actual", "Cambiar a"].map((h) => <th key={h} style={th}>{h}</th>)}</tr></thead>
        <tbody>{d.impuestos.reglas.map((r: any) => (<tr key={r.id}>
          <td style={td}><b>{r.codigo}</b><div style={{ color: "#666" }}>{r.nombre}</div></td>
          <td style={td}>{r.destino}</td>
          <td style={td}>{selectInst(nuevos[r.codigo] ?? "", (v) => setNuevos({ ...nuevos, [r.codigo]: v }))} <button onClick={() => cambiarDestino(r.codigo)}>Guardar</button></td>
        </tr>))}</tbody></table>
    </section>
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Cuentas de configuración</h2>
      <p><b>Tributos</b>: recibe los impuestos. Actual: {d.configuracion.cuenta_tributos}.</p>
      <p><b>Origen de la RBU</b>: de aquí sale el bono semanal. Actual: {d.configuracion.cuenta_rbu_origen}. Si no se configura, se usa la Reserva.</p>
      <p style={{ color: "#555", fontSize: 14 }}>Ambas cuentas deben ser institucionales. Para cambiarlas, elige una cuenta y confirma.</p>
      <RowConfig etiqueta="Tributos" opciones={opcionesInst} onGuardar={(c) => cambiarConfig("cuenta_tributos", c)} />
      <RowConfig etiqueta="Origen de la RBU" opciones={opcionesInst} onGuardar={(c) => cambiarConfig("cuenta_rbu_origen", c)} />
    </section>
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Cuentas institucionales y operación con Junior</h2>
      <p>Las cuentas de esta lista son las únicas que pueden operar con cuentas Junior, además de las propias Junior. Las marcadas como <b>«Junior»</b> pueden recibir o enviar desde cuentas Junior. Las demás, no. Las cuentas que se marcan sin aprobador registrado aparecen como pendientes.</p>
      <table style={{ width: "100%", borderCollapse: "collapse" }}><thead><tr>{["Cuenta", "Motivo", "Opera con Junior", "Aprobación", ""].map((h) => <th key={h} style={th}>{h}</th>)}</tr></thead>
        <tbody>{d.institucionales.lista.map((i: any) => (<tr key={i.cuenta}>
          <td style={td}>{i.etiqueta}</td><td style={td}>{i.motivo}</td>
          <td style={td}>{i.junior ? "✓ sí" : "✗ no"}</td>
          <td style={td}>{i.aprobada ? "registrada" : <span style={{ color: "#a60" }}>pendiente</span>}</td>
          <td style={td}><button onClick={() => marcarJunior(i.cuenta, i.motivo, !i.junior)}>{i.junior ? "Quitar acceso Junior" : "Dar acceso Junior"}</button></td>
        </tr>))}</tbody></table>
      <h3>Declarar una cuenta institucional nueva</h3>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <select value={cuentaNueva} onChange={(e) => setCuentaNueva(e.target.value)}><option value="">— elige una cuenta —</option>
          {d.cuentas.lista.map((c: any) => <option key={c.id} value={c.id}>{c.etiqueta}</option>)}</select>
        <label><input type="checkbox" checked={junior} onChange={(e) => setJunior(e.target.checked)} /> puede operar con Junior</label>
        <button onClick={añadirInstitucional}>Declarar institucional</button>
      </div>
    </section>
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Capitalia y el pago de impuestos Junior</h2>
      <p>Capitalia paga en nombre de los usuarios Junior todos los impuestos, mensuales y de cualquier otra clase. El obligado sigue siendo el usuario Junior, y así queda en cada recibo. El pagador es la cuenta principal de la entidad que se designe aquí.</p>
      <p>Entidad designada: <b>{d.junior.capitalia}</b>. Pagador activo: <b>{d.ajustes.capitalia_asume_impuestos_junior === true || d.ajustes.capitalia_asume_impuestos_junior === "true" ? "Capitalia" : "Placeta Junior"}</b>.</p>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        <select value={bancoCap} onChange={(e) => setBancoCap(e.target.value)}><option value="">— elige la entidad —</option>
          {d.listas.bancos.map((b: any) => <option key={b.id} value={b.id}>{b.nombre}</option>)}</select>
        <button onClick={async () => { if (bancoCap && await dlg.confirm("Designar esta entidad como pagadora de los impuestos Junior?")) ejecutar("plone27_set_junior_payer", { p_bank: bancoCap }, "Entidad designada."); }}>Designar</button>
      </div>
    </section>
  </>);
}

function RowConfig({ etiqueta, opciones, onGuardar }: { etiqueta: string; opciones: { id: string; etiqueta: string }[]; onGuardar: (c: string) => void }) {
  const [v, setV] = useState("");
  return (<div style={{ display: "flex", gap: 8, alignItems: "center", marginTop: 8 }}>
    <span style={{ minWidth: 140 }}>{etiqueta}:</span>
    <select value={v} onChange={(e) => setV(e.target.value)}><option value="">— elige cuenta institucional —</option>
      {opciones.map((o) => <option key={o.id} value={o.id}>{o.etiqueta}</option>)}</select>
    <button onClick={() => onGuardar(v)}>Guardar</button></div>);
}
