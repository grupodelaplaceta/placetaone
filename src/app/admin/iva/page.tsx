"use client";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { dlg } from "../ui";

// Transferencias comerciales sin IVA: detección, propuesta, aprobación y reporte.
type H = { id: string; kind: string; status: string; severity: string; amount: number; iva_due: number | null; receptor: string; pagador: string;
  propuesta_accion: string | null; propuesto_por: string | null; motivo: string | null; detected_at: string; receipt_id: string | null };
const TIPO: Record<string, string> = { cobro_comercial_sin_iva: "Cobro comercial sin IVA", patron_comercial_personal: "Patrón comercial en cuenta personal", fraccionamiento: "Fraccionamiento" };
const EXPLICA: Record<string, string> = {
  cobro_comercial_sin_iva: "Una transferencia entró en una cuenta de empresa y no hay venta registrada. Si fue una venta, el IVA no se liquidó.",
  patron_comercial_personal: "Una cuenta personal recibe pagos de muchos pagadores distintos. Puede estar actuando como comercio. Es una señal para revisar, no una prueba.",
  fraccionamiento: "Varias transferencias pequeñas del mismo pagador al mismo comercio en un día suman más del umbral. Puede ser un intento de eludir el IVA o el control.",
};
const pz = (n: number | null | undefined) => n == null ? "—" : `${Number(n).toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} Pz`;
const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
const th = { textAlign: "left", padding: "6px 8px", borderBottom: "1px solid #ddd", fontSize: 13 } as const;
const td = { padding: "6px 8px", borderBottom: "1px solid #eee", fontSize: 13, verticalAlign: "top" } as const;

export default function IVA() {
  const hoy = new Date(); const primero = new Date(hoy.getFullYear(), hoy.getMonth(), 1).toISOString().slice(0, 10);
  const [rows, setRows] = useState<H[]>([]); const [informe, setInforme] = useState<any>(null);
  const [desde, setDesde] = useState(primero); const [hasta, setHasta] = useState(hoy.toISOString().slice(0, 10));
  const [filtro, setFiltro] = useState("abierto"); const [msg, setMsg] = useState("");

  const cargar = useCallback(async () => {
    try { const j = await api(`/api/admin/iva?desde=${desde}&hasta=${hasta}`); setRows(j.hallazgos); setInforme(j.informe); }
    catch (e) { setMsg((e as Error).message); }
  }, [desde, hasta]);
  useEffect(() => { cargar(); }, [cargar]);

  const escanear = async () => {
    if (!(await dlg.confirm("Buscar ahora cobros comerciales sin IVA en los últimos 30 días? No mueve dinero; solo registra hallazgos."))) return;
    try {
      const r = await api("/api/rpc/plone27_iva_scan", "POST", { p_desde: new Date(Date.now() - 30 * 864e5).toISOString(), p_hasta: new Date(Date.now() + 6e4).toISOString() });
      setMsg(`Escaneo: ${JSON.stringify(r.result)}`); cargar();
    } catch (e) { setMsg((e as Error).message); }
  };
  const proponer = async (h: H, accion: "regularizar" | "descartar") => {
    const motivo = await dlg.prompt(accion === "regularizar" ? "Motivo de la regularización (mín. 10 caracteres)" : "Motivo para descartar (mín. 10 caracteres)");
    if (!motivo) return;
    try { await api("/api/rpc/plone27_iva_propose", "POST", { p_finding: h.id, p_accion: accion, p_motivo: motivo }); setMsg("Propuesta registrada. Otra persona debe aprobarla."); cargar(); }
    catch (e) { setMsg((e as Error).message); }
  };
  const aprobar = async (h: H) => {
    if (!(await dlg.confirm(`Aprobar: ${h.propuesta_accion}. ${h.propuesta_accion === "regularizar" ? "Se emitirá el recibo de IVA a cargo del receptor." : "El hallazgo se cerrará sin recibo."}`))) return;
    try { const r = await api("/api/rpc/plone27_iva_approve", "POST", { p_finding: h.id }); setMsg(r.result ? "Regularizado: recibo emitido." : "Descartado."); cargar(); }
    catch (e) { setMsg((e as Error).message); }
  };
  const csv = () => {
    const cab = ["fecha", "tipo", "severidad", "estado", "receptor", "pagador", "importe", "iva_estimado", "propuesta", "motivo"];
    const lineas = rows.map((h) => [h.detected_at, TIPO[h.kind] ?? h.kind, h.severity, h.status, h.receptor, h.pagador, h.amount, h.iva_due ?? "", h.propuesta_accion ?? "", (h.motivo ?? "").replace(/"/g, "'")]
      .map((v) => `"${String(v)}"`).join(";"));
    const blob = new Blob([[cab.join(";"), ...lineas].join("\n")], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `iva_hallazgos_${desde}_${hasta}.csv`; a.click();
  };

  const visibles = rows.filter((h) => filtro === "todos" || h.status === filtro);
  const est = informe?.hallazgos_por_estado ?? {};
  const tarjeta = (t: string, v: string) => <div style={{ border: "1px solid #ddd", borderRadius: 8, padding: "8px 12px", minWidth: 160 }}>
    <div style={{ fontSize: 12, color: "#777" }}>{t}</div><div style={{ fontSize: 18, fontWeight: 600 }}>{v}</div></div>;

  return (<>
    <h1>IVA · transferencias comerciales</h1>
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Qué es esta pantalla</h2>
      <p>El escaneo busca cobros comerciales que no tienen venta registrada, patrones de comercio en cuentas personales y fraccionamientos. Es una <b>detección</b>: no mueve dinero. Cada hallazgo se revisa aquí.</p>
      <ol style={{ paddingLeft: 20 }}>
        <li><b>Proponer</b>: el fiscal indica si se regulariza o se descarta, con un motivo.</li>
        <li><b>Aprobar</b>: otra persona distinta confirma. Solo entonces se emite el recibo de IVA.</li>
        <li><b>Informe</b>: IVA pendiente y regularizado por periodo, exportable a CSV.</li>
      </ol>
      <p style={{ color: "#555", fontSize: 14 }}>Base de la norma: el IVA es el 12 % sobre el precio base (Art. 4.4; Arts. T26 y T106). Criterio de lectura de los importes: <b>exclusivo</b> por defecto, es decir, el importe detectado es la base.</p>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center", marginTop: 8 }}>
        <label>Desde <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></label>
        <label>Hasta <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} /></label>
        <button onClick={cargar}>Actualizar informe</button>
        <button onClick={escanear}>Buscar ahora (últimos 30 días)</button>
      </div>
      {msg && <p role="status" style={{ color: "#345", marginBottom: 0 }}>{msg}</p>}
    </section>
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Informe del periodo</h2>
      {informe && <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
        {tarjeta("Ventas registradas", String(informe.ventas_registradas?.operaciones ?? 0))}
        {tarjeta("Base de ventas", pz(informe.ventas_registradas?.base))}
        {tarjeta("IVA de ventas", pz(informe.ventas_registradas?.iva))}
        {tarjeta("Hallazgos abiertos", String(est.abierto?.n ?? 0))}
        {tarjeta("IVA pendiente de liquidar", pz(informe.iva_pendiente_de_liquidar))}
        {tarjeta("IVA regularizado", pz(informe.iva_regularizado))}
      </div>}
      <button style={{ marginTop: 12 }} onClick={csv}>Exportar CSV ({visibles.length} filas)</button>
    </section>
    <section style={box}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2 style={{ margin: 0 }}>Hallazgos</h2>
        <select value={filtro} onChange={(e) => setFiltro(e.target.value)}>
          <option value="abierto">Abiertos</option><option value="regularizado">Regularizados</option><option value="descartado">Descartados</option><option value="todos">Todos</option>
        </select>
      </div>
      {visibles.length === 0 && <p style={{ color: "#777" }}>No hay hallazgos en esta vista.</p>}
      {visibles.length > 0 && <table style={{ width: "100%", borderCollapse: "collapse", marginTop: 8 }}>
        <thead><tr>{["Fecha", "Tipo", "Severidad", "Receptor", "Pagador", "Importe", "IVA estimado", "Estado", "Acciones"].map((h) => <th key={h} style={th}>{h}</th>)}</tr></thead>
        <tbody>{visibles.map((h) => (<tr key={h.id}>
          <td style={td}>{new Date(h.detected_at).toLocaleDateString("es")}</td>
          <td style={td}><b>{TIPO[h.kind] ?? h.kind}</b><div style={{ color: "#666", fontSize: 12, maxWidth: 280 }}>{EXPLICA[h.kind]}</div></td>
          <td style={td}>{h.severity}</td>
          <td style={td}>{h.receptor}</td><td style={td}>{h.pagador || "—"}</td>
          <td style={td}>{pz(h.amount)}</td><td style={td}>{pz(h.iva_due)}</td>
          <td style={td}>{h.status}{h.propuesta_accion && h.status === "abierto" && <div style={{ color: "#a60", fontSize: 12 }}>Propuesta: {h.propuesta_accion}<br />«{h.motivo}»</div>}</td>
          <td style={td}>{h.status === "abierto" && !h.propuesta_accion && <>
            <button onClick={() => proponer(h, "regularizar")}>Proponer regularizar</button>{" "}
            <button onClick={() => proponer(h, "descartar")}>Proponer descartar</button></>}
            {h.status === "abierto" && h.propuesta_accion && <button onClick={() => aprobar(h)}>Aprobar</button>}
          </td>
        </tr>))}</tbody></table>}
    </section>
  </>);
}
