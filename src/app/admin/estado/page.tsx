"use client";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { Modal } from "../ui";
type C = { name?: string; check?: string; ok?: boolean; severity?: string; count?: number; detail: string; ms?: number };
type H = { at: string; apis: C[]; config: C[]; integrity: C[]; security: C[]; errors: string[] };
const dot = (c: string) => <span style={{ display: "inline-block", width: 10, height: 10, borderRadius: 5, background: c, marginRight: 8 }} />;
const sev = (c: C) => (c.count === 0 ? "#2a7" : c.severity === "critical" ? "#c33" : c.severity === "warning" ? "#e90" : "#58a");
const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
export default function Estado() {
  const [h, setH] = useState<H | null>(null); const [err, setErr] = useState(""); const [sel, setSel] = useState<C | null>(null); const [busy, setBusy] = useState(false);
  const load = useCallback(async () => { setBusy(true); try { setH(await api("/api/admin/health")); setErr(""); } catch (e) { setErr((e as Error).message); } setBusy(false); }, []);
  useEffect(() => { load(); }, [load]);
  const bad = h ? [...h.apis, ...h.config].filter(c => !c.ok).length + [...h.integrity, ...h.security].filter(c => (c.count ?? 0) > 0 && c.severity === "critical").length : 0;
  const rows = (list: C[], isData: boolean) => list.map((c, i) => <tr key={i} onClick={() => setSel(c)} style={{ cursor: "pointer" }}><td style={{ padding: 6 }}>{dot(isData ? sev(c) : c.ok ? "#2a7" : "#c33")}{c.name ?? c.check}</td>
    <td style={{ color: "#555" }}>{isData ? ((c.count ?? 0) === 0 ? "Correcto" : `${c.count} caso(s)`) : c.detail}</td><td style={{ textAlign: "right", color: "#777" }}>{c.ms !== undefined ? `${c.ms} ms` : ""}</td></tr>);
  return (<><h1>Estado del sistema</h1>{err && <p role="alert" style={{ color: "#a33" }}>{err}</p>}
    <p>{h && <b style={{ color: bad ? "#c33" : "#2a7" }}>{bad ? `⚠ ${bad} problema(s) crítico(s)` : "✓ Sin problemas críticos"}</b>} <button disabled={busy} onClick={load}>{busy ? "Comprobando…" : "Volver a comprobar"}</button> {h && <small style={{ color: "#777" }}>{new Date(h.at).toLocaleString("es")}</small>}</p>
    {h && <>
      <section style={box}><h2 style={{ marginTop: 0 }}>APIs</h2><p style={{ color: "#555" }}>Cada API debe responder y rechazar las llamadas sin credenciales (401/403). Un 500 o un tiempo agotado indica caída.</p><table style={{ width: "100%", fontSize: 14 }}><tbody>{rows(h.apis, false)}</tbody></table></section>
      <section style={box}><h2 style={{ marginTop: 0 }}>Configuración y conexiones</h2><table style={{ width: "100%", fontSize: 14 }}><tbody>{rows(h.config, false)}</tbody></table></section>
      <section style={box}><h2 style={{ marginTop: 0 }}>Comprobaciones de seguridad</h2><table style={{ width: "100%", fontSize: 14 }}><tbody>{rows(h.security, true)}</tbody></table></section>
      <section style={box}><h2 style={{ marginTop: 0 }}>Incoherencias de datos</h2><table style={{ width: "100%", fontSize: 14 }}><tbody>{rows(h.integrity, true)}</tbody></table></section>
      {h.errors.length > 0 && <p role="alert" style={{ color: "#a33" }}>No se pudieron ejecutar algunos informes (¿falta la migración 0010?): {h.errors.join(" · ")}</p>}</>}
    <Modal open={!!sel} title={sel?.name ?? sel?.check ?? ""} onClose={() => setSel(null)}>{sel && <><p>{sel.detail || "Sin más detalle."}</p>{sel.count !== undefined && <p>Casos detectados: <b>{sel.count}</b> · Gravedad: <b>{sel.severity}</b></p>}
      <p style={{ color: "#555" }}>{sel.count ? "Revisa los registros afectados en Registros y Auditoría. Si es crítico, no operes con datos reales hasta resolverlo." : sel.ok === false ? "Revisa la configuración en Vercel o los registros del despliegue." : "Todo correcto."}</p></>}</Modal></>);
}
