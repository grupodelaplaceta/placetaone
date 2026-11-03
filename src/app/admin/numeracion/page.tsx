"use client";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
type F = { kind: string; version: number; prefix: string; year_scoped: boolean; width: number; status: string };
const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
export default function Numeracion() {
  const [rows, setRows] = useState<F[]>([]); const [msg, setMsg] = useState(""); const [f, setF] = useState({ kind: "REC", prefix: "PL27-REC-", year: "true", width: "7", reason: "" });
  const load = useCallback(() => { api("/api/admin/r/numbering").then(setRows).catch(e => setMsg(e.message)); }, []);
  useEffect(() => { load(); }, [load]);
  const rpc = async (fn: string, body: object) => { try { const j = await api(`/api/rpc/${fn}`, "POST", body); setMsg(JSON.stringify(j.result ?? "Hecho")); load(); } catch (e) { setMsg((e as Error).message); } };
  return (<><h1>Numeración e identificadores</h1>{msg && <p role="status" style={{ background: "#f6f5f1", padding: 8 }}>{msg}</p>}
    <section style={box}><h2>Formatos</h2><table style={{ width: "100%", fontSize: 14 }}><thead><tr style={{ textAlign: "left" }}><th>Tipo</th><th>v</th><th>Prefijo</th><th>Por año</th><th>Dígitos</th><th>Estado</th><th /></tr></thead>
      <tbody>{rows.map(r => <tr key={r.kind + r.version}><td>{r.kind}</td><td>{r.version}</td><td><code>{r.prefix}</code></td><td>{r.year_scoped ? "✓" : "✗"}</td><td>{r.width}</td><td>{r.status}</td>
        <td>{r.status === "draft" && <><button onClick={() => rpc("plone27_numbering_simulate", { p_kind: r.kind, p_version: r.version })}>Simular</button> <button onClick={() => confirm("¿Publicar? Se aplicará a los registros nuevos.") && rpc("plone27_numbering_publish", { p_kind: r.kind, p_version: r.version })}>Publicar</button></>}</td></tr>)}</tbody></table></section>
    <section style={box}><h2>Proponer nueva versión</h2><form onSubmit={e => { e.preventDefault(); rpc("plone27_numbering_propose", { p_kind: f.kind, p_prefix: f.prefix, p_year: f.year === "true", p_width: Number(f.width), p_reason: f.reason }); }} style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
      <input value={f.kind} onChange={e => setF({ ...f, kind: e.target.value })} placeholder="Tipo (REC, TRF…)" size={8} /><input value={f.prefix} onChange={e => setF({ ...f, prefix: e.target.value })} placeholder="PL27-XXX-" />
      <select value={f.year} onChange={e => setF({ ...f, year: e.target.value })}><option value="true">Reinicia cada año</option><option value="false">Contador global</option></select>
      <input type="number" min={4} max={15} value={f.width} onChange={e => setF({ ...f, width: e.target.value })} style={{ width: 70 }} /><input value={f.reason} onChange={e => setF({ ...f, reason: e.target.value })} placeholder="Motivo" required /><button>Proponer</button></form>
      <p style={{ color: "#777" }}>Los identificadores ya emitidos no cambian nunca. El formato nuevo solo afecta a los registros que se creen después de publicarlo.</p></section></>);
}
