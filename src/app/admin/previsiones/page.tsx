"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api } from "@/lib/api";

// Previsión: qué va a pasar, cuándo y si la cuenta puede pagarlo.
type P = { fecha: string; tipo: string; referencia: string; cuenta: string | null; iban: string | null; nombre: string | null; importe: number | null; estado: string; detalle: string };
const pz = (n: number | null | undefined) => (n == null ? "—" : `${Number(n).toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} Pz`);
const ESTADO: Record<string, { c: string; t: string }> = {
  cobrable: { c: "#2e7d32", t: "Cobrable" }, "sin fondos": { c: "#c62828", t: "Sin fondos" }, vencido: { c: "#6d1b1b", t: "Vencido" },
  programado: { c: "#1565c0", t: "Programado" }, estimado: { c: "#757575", t: "Estimado" }, cerrado: { c: "#2e7d32", t: "Cerrado" }, disponible: { c: "#8a6d00", t: "Disponible" },
};
const badge = (e: string) => <span style={{ background: ESTADO[e]?.c ?? "#555", color: "#fff", borderRadius: 6, padding: "2px 8px", fontSize: 12 }}>{ESTADO[e]?.t ?? e}</span>;
const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;

export default function Previsiones() {
  const hoy = new Date().toISOString().slice(0, 10);
  const en60 = new Date(Date.now() + 60 * 864e5).toISOString().slice(0, 10);
  const [desde, setDesde] = useState(hoy); const [hasta, setHasta] = useState(en60);
  const [filas, setFilas] = useState<P[]>([]); const [kpi, setKpi] = useState<Record<string, any>>({});
  const [tipo, setTipo] = useState("todos"); const [estado, setEstado] = useState("todos"); const [q, setQ] = useState("");
  const [cargando, setCargando] = useState(false); const [error, setError] = useState("");

  const cargar = useCallback(async () => {
    setCargando(true); setError("");
    try {
      const j = await api(`/api/admin/previsiones?desde=${desde}&hasta=${hasta}`);
      setFilas(Array.isArray(j.previsiones) ? j.previsiones : []); setKpi(j.kpis ?? {});
    } catch (e) { setError((e as Error).message); setFilas([]); }
    finally { setCargando(false); }
  }, [desde, hasta]);
  useEffect(() => { cargar(); }, [cargar]);

  const tipos = useMemo(() => Array.from(new Set(filas.map((f) => f.tipo))).sort(), [filas]);
  const visibles = useMemo(() => filas.filter((f) =>
    (tipo === "todos" || f.tipo === tipo) && (estado === "todos" || f.estado === estado) &&
    (!q || `${f.referencia} ${f.iban ?? ""} ${f.nombre ?? ""} ${f.detalle}`.toLowerCase().includes(q.toLowerCase()))), [filas, tipo, estado, q]);

  const porDia = useMemo(() => {
    const m = new Map<string, P[]>();
    visibles.forEach((f) => m.set(f.fecha, [...(m.get(f.fecha) ?? []), f]));
    return Array.from(m.entries());
  }, [visibles]);

  const porTipo = useMemo(() => {
    const m: Record<string, number> = {};
    visibles.forEach((f) => { m[f.tipo] = (m[f.tipo] ?? 0) + Number(f.importe ?? 0); });
    const max = Math.max(1, ...Object.values(m));
    return Object.entries(m).sort((a, b) => b[1] - a[1]).map(([k, v]) => ({ k, v, p: Math.round((v / max) * 100) }));
  }, [visibles]);

  const sinFondos = visibles.filter((f) => f.estado === "sin fondos");
  const vencidos = visibles.filter((f) => f.estado === "vencido");
  const total = visibles.reduce((a, f) => a + Number(f.importe ?? 0), 0);

  const csv = () => {
    const cab = ["fecha", "tipo", "referencia", "iban", "nombre", "importe", "estado", "detalle"];
    const filasCsv = visibles.map((f) => [f.fecha, f.tipo, f.referencia, f.iban ?? "", f.nombre ?? "", f.importe ?? "", f.estado, f.detalle].map((v) => `"${String(v).split('"').join("'")}"`).join(";"));
    const blob = new Blob([[cab.join(";"), ...filasCsv].join("\n")], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a"); a.href = URL.createObjectURL(blob); a.download = `previsiones_${desde}_${hasta}.csv`; a.click();
  };

  const kcard = (t: string, v: string, sub?: string, color?: string) => (
    <div style={{ border: "1px solid #ddd", borderRadius: 10, padding: "10px 14px", minWidth: 170, background: "#fff" }}>
      <div style={{ fontSize: 12, color: "#777" }}>{t}</div>
      <div style={{ fontSize: 20, fontWeight: 600, color: color ?? "#222" }}>{v}</div>
      {sub && <div style={{ fontSize: 12, color: "#777" }}>{sub}</div>}
    </div>);

  return (<>
    <h1>Previsión de movimientos</h1>
    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Cómo leer esta pantalla</h2>
      <p>Cada fila es algo que va a ocurrir: un impuesto que vence, una cuota, una suscripción, una nómina, una transferencia programada, un cierre o una caducidad de RBU. La columna <b>Estado</b> dice si la cuenta puede pagarlo ahora: <b>cobrable</b> significa que tiene fondos; <b>sin fondos</b> significa que el cobro fallará y se reintentará cada día. <b>Estimado</b> es una cifra calculada aún no emitida.</p>
      <p style={{ color: "#555", fontSize: 14 }}>Las previsiones se calculan sobre el libro en cada consulta. Lo que aparece aquí es lo que el cron diario ejecutará, no un compromiso adicional.</p>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <label>Desde <input type="date" value={desde} onChange={(e) => setDesde(e.target.value)} /></label>
        <label>Hasta <input type="date" value={hasta} onChange={(e) => setHasta(e.target.value)} /></label>
        <button onClick={cargar} disabled={cargando}>{cargando ? "Cargando…" : "Actualizar"}</button>
        <button onClick={csv} disabled={!visibles.length}>Exportar CSV ({visibles.length})</button>
      </div>
      {error && <p role="alert" style={{ color: "#a33" }}>No se han podido cargar las previsiones: {error}</p>}
    </section>

    <section style={{ display: "flex", flexWrap: "wrap", gap: 10, marginBottom: 16 }}>
      {kcard("Pendiente de cobro", pz(kpi.recibos_pendientes_importe), `${kpi.recibos_pendientes ?? 0} recibos`)}
      {kcard("Recibos vencidos", String(kpi.recibos_vencidos ?? 0), "riesgo de recargo T57", (kpi.recibos_vencidos ?? 0) > 0 ? "#c62828" : undefined)}
      {kcard("Cuotas pendientes", pz(kpi.cuotas_pendientes_importe), `${kpi.planes_activos ?? 0} planes activos`)}
      {kcard("Nóminas en el rango", String(filas.filter((f) => f.tipo === "Nómina").length), `${kpi.contratos_activos ?? 0} contratos`)}
      {kcard("RBU disponible", pz(kpi.rbu_disponible), "sin reclamar")}
      {kcard("IVA abierto", String(kpi.hallazgos_iva_abiertos ?? 0), "hallazgos sin resolver", (kpi.hallazgos_iva_abiertos ?? 0) > 0 ? "#a60" : undefined)}
      {kcard("Retenidas", String(kpi.declaraciones_retenidas ?? 0), "pendientes de aprobación", (kpi.declaraciones_retenidas ?? 0) > 0 ? "#a60" : undefined)}
      {kcard("Incidencias", String(kpi.incidencias_abiertas ?? 0), "abiertas", (kpi.incidencias_abiertas ?? 0) > 0 ? "#c62828" : undefined)}
      {kcard("Certificación", String(kpi.certificacion ?? "—"), `último cierre: ${kpi.ultimo_cierre ?? "ninguno"}`, kpi.certificacion === "OK" ? "#2e7d32" : undefined)}
    </section>

    {(sinFondos.length > 0 || vencidos.length > 0) && <section style={{ ...box, borderColor: "#e8b9a8", background: "#fff6f3" }}>
      <h2 style={{ marginTop: 0, color: "#7a2e1d" }}>Atención en el rango</h2>
      <p>{sinFondos.length} movimientos sin fondos por {pz(sinFondos.reduce((a, f) => a + Number(f.importe ?? 0), 0))} y {vencidos.length} vencidos por {pz(vencidos.reduce((a, f) => a + Number(f.importe ?? 0), 0))}. Los cobros se reintentan cada día; los vencidos generan recargo según los días de retraso (Art. T57).</p>
      <button onClick={() => { setEstado("sin fondos"); }}>Ver sin fondos</button>{" "}<button onClick={() => { setEstado("vencido"); }}>Ver vencidos</button>
    </section>}

    <section style={box}>
      <h2 style={{ marginTop: 0 }}>Importe por tipo en el rango</h2>
      {porTipo.length === 0 && <p style={{ color: "#777" }}>Sin movimientos en el rango.</p>}
      {porTipo.map((t) => <div key={t.k} style={{ display: "grid", gridTemplateColumns: "220px 1fr 160px", gap: 8, alignItems: "center", fontSize: 14, marginBottom: 6 }}>
        <span>{t.k}</span><div style={{ background: "#eee", borderRadius: 4, height: 12 }}><div style={{ width: `${t.p}%`, background: "#3a6", height: 12, borderRadius: 4 }} /></div>
        <b style={{ textAlign: "right" }}>{pz(t.v)}</b></div>)}
      <p style={{ marginBottom: 0, fontWeight: 600 }}>Total del rango: {pz(total)}</p>
    </section>

    <section style={box}>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center", marginBottom: 8 }}>
        <select value={tipo} onChange={(e) => setTipo(e.target.value)}><option value="todos">Todos los tipos</option>{tipos.map((t) => <option key={t} value={t}>{t}</option>)}</select>
        <select value={estado} onChange={(e) => setEstado(e.target.value)}><option value="todos">Todos los estados</option>{Object.keys(ESTADO).map((k) => <option key={k} value={k}>{ESTADO[k].t}</option>)}</select>
        <input placeholder="Buscar referencia, IBAN o nombre" value={q} onChange={(e) => setQ(e.target.value)} style={{ minWidth: 260 }} />
      </div>
      {!cargando && porDia.length === 0 && <p style={{ color: "#777" }}>No hay movimientos con estos filtros.</p>}
      {porDia.map(([dia, lista]) => (
        <div key={dia} style={{ marginBottom: 12 }}>
          <div style={{ display: "flex", justifyContent: "space-between", background: "#f4f4f1", padding: "6px 10px", borderRadius: 6, fontSize: 14 }}>
            <b>{new Date(dia + "T12:00:00").toLocaleDateString("es", { weekday: "long", day: "numeric", month: "long" })}</b>
            <span>{lista.length} movimientos · {pz(lista.reduce((a, f) => a + Number(f.importe ?? 0), 0))}</span></div>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}><tbody>
            {lista.map((f, i) => (<tr key={i} style={{ borderBottom: "1px solid #eee" }}>
              <td style={{ padding: "6px 8px", width: 150 }}>{f.tipo}</td>
              <td style={{ padding: "6px 8px" }}>{f.referencia}<div style={{ color: "#777", fontSize: 12 }}>{f.detalle}</div></td>
              <td style={{ padding: "6px 8px" }}>{f.iban ?? "—"}<div style={{ color: "#777", fontSize: 12 }}>{f.nombre ?? ""}</div></td>
              <td style={{ padding: "6px 8px", textAlign: "right" }}>{pz(f.importe)}</td>
              <td style={{ padding: "6px 8px" }}>{badge(f.estado)}</td>
            </tr>))}
          </tbody></table>
        </div>))}
    </section>
  </>);
}
