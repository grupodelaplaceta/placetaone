"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
type D = { alerts: { alerta: string; n: number }[]; audit: { id: number; action: string; entity: string; entity_id: string; at: string }[] };
export default function Panel() {
  const [d, setD] = useState<D | null>(null); const [err, setErr] = useState("");
  useEffect(() => { api("/api/admin/overview").then(setD).catch(e => setErr(e.message)); }, []);
  const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
  return (<><h1>Panel</h1>{err && <p role="alert" style={{ color: "#a33" }}>{err}</p>}{d && <>
    <section style={box}><h2>Alertas</h2>{(d.alerts ?? []).map(a => <span key={a.alerta} style={{ marginRight: 16, color: a.n > 0 ? "#a33" : "#2a7" }}>{a.alerta.replaceAll("_", " ")}: <b>{a.n}</b></span>)}</section>
    <section style={box}><h2>Auditoría reciente</h2><table style={{ width: "100%", fontSize: 14 }}><tbody>{(d.audit ?? []).map(a => <tr key={a.id}><td>{new Date(a.at).toLocaleString("es")}</td><td>{a.action}</td><td>{a.entity}</td><td style={{ fontFamily: "monospace" }}>{a.entity_id}</td></tr>)}</tbody></table></section></>}</>);
}
