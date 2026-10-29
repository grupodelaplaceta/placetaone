"use client";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Sheet, dlg } from "./ui";
type Row = Record<string, unknown>;
export type Field = { k: string; l: string; ref?: string; lab?: string[]; showIf?: (f: Record<string, string>) => boolean; hint?: string; t?: "multi" | "text" | "number" | "select" | "list" | "date" | "bool"; o?: string[] };
export type Action = { l: string; body: (r: Row, v?: string) => object | null; ask?: boolean; prompt?: string; del?: boolean };
const fmt = (v: unknown) => v === null || v === undefined ? "—" : Array.isArray(v) ? v.join(", ") : typeof v === "boolean" ? (v ? "✓" : "✗") : String(v);
export function Resource(p: { res: string; title: string; cols: Field[]; create?: Field[]; actions?: Action[]; filter?: Record<string, string>; href?: (r: Row) => string; help?: string }) {
  const [rows, setRows] = useState<Row[]>([]); const [msg, setMsg] = useState(""); const [form, setForm] = useState<Record<string, string>>({}); const [open, setOpen] = useState(false);
  const [refs, setRefs] = useState<Record<string, Row[]>>({});
  useEffect(() => { if (open) (p.create ?? []).filter(f => f.ref).forEach(f => { api(`/api/admin/r/${f.ref}`).then(d => setRefs(r => ({ ...r, [f.ref!]: d }))).catch(() => {}); }); }, [open]); // eslint-disable-line react-hooks/exhaustive-deps
  const qs = new URLSearchParams(p.filter ?? {}).toString();
  const load = useCallback(async () => { try { setRows(await api(`/api/admin/r/${p.res}${qs ? "?" + qs : ""}`)); } catch (e) { setMsg((e as Error).message); } }, [p.res, qs]);
  useEffect(() => { load(); }, [load]);
  const submit = async (e: React.FormEvent) => { e.preventDefault(); const body: Record<string, unknown> = { ...(p.filter ?? {}) };
    for (const f of p.create ?? []) { const v = form[f.k]; if (v === undefined || v === "") continue; body[f.k] = f.t === "number" ? Number(v) : f.t === "list" || f.t === "multi" ? v.split(",").map(x => x.trim()).filter(Boolean) : f.t === "bool" ? v === "true" : v; }
    try { const j = await api(`/api/admin/r/${p.res}`, "POST", body); setForm({}); setOpen(false); setMsg(j.secret ? `Guarda este secreto, solo se muestra una vez: ${j.secret}` : "Creado"); load(); } catch (e) { setMsg((e as Error).message); } };
  const act = async (r: Row, a: Action) => { const v = a.prompt ? (await dlg.prompt(a.prompt)) ?? undefined : undefined; if (a.prompt && !v) return; const b = a.body(r, v ?? undefined); if (!b || (!a.prompt && a.ask !== false && !(await dlg.confirm(`${a.l}?`)))) return;
    try { if (a.del) await api(`/api/admin/r/${p.res}?account_id=${r.account_id}&user_id=${r.user_id}`, "DELETE"); else await api(`/api/admin/r/${p.res}?id=${r.id ?? r.user_id ?? r.account_id ?? r.customer_id}`, "PATCH", b); setMsg("Hecho"); load(); } catch (e) { setMsg((e as Error).message); } };
  const th = { textAlign: "left", padding: "6px 8px", borderBottom: "1px solid #ddd" } as const;
  return (<section style={{ background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 }}>
    <div style={{ display: "flex", justifyContent: "space-between" }}><h2 style={{ margin: 0 }}>{p.title}</h2>{p.create && <button onClick={() => setOpen(!open)}>{open ? "Cancelar" : "+ Nuevo"}</button>}</div>
    {p.help && <p style={{ color: "#555", margin: "8px 0" }}>ℹ️ {p.help}</p>}
    {msg && <p role="status" style={{ wordBreak: "break-all", background: "#f6f5f1", padding: 8 }}>{msg}</p>}
    <Sheet open={open} title={"Nuevo · " + p.title} onClose={() => setOpen(false)}><form onSubmit={submit} style={{ display: "grid", gap: 12 }}>{p.create!.filter(f => !f.showIf || f.showIf(form)).map(f => <label key={f.k} style={{ fontSize: 13 }}>{f.l}{f.hint && <small style={{ display: "block", color: "#777" }}>{f.hint}</small>}<br />
      {f.t === "multi" ? <span style={{ display: "block", maxWidth: 260 }}>{(f.o ?? []).map(o => <label key={o} style={{ display: "block" }}><input type="checkbox" checked={(form[f.k] ?? "").split(",").includes(o)} onChange={e => { const cur = (form[f.k] ?? "").split(",").filter(Boolean); setForm({ ...form, [f.k]: (e.target.checked ? [...cur, o] : cur.filter(x => x !== o)).join(",") }); }} /> {o}</label>)}</span> : f.ref ? <select value={form[f.k] ?? ""} onChange={e => setForm({ ...form, [f.k]: e.target.value })}><option value="">—</option>{(refs[f.ref] ?? []).map(o => <option key={String(o.id)} value={String(o.id)}>{(f.lab ?? ["name"]).map(k => fmt(o[k])).join(" · ")}</option>)}</select> : f.t === "select" || f.t === "bool" ? <select value={form[f.k] ?? ""} onChange={e => setForm({ ...form, [f.k]: e.target.value })}><option value="">—</option>{(f.o ?? ["true", "false"]).map(o => <option key={o}>{o}</option>)}</select>
        : <input type={f.t === "number" ? "number" : f.t === "date" ? "date" : "text"} step="any" value={form[f.k] ?? ""} onChange={e => setForm({ ...form, [f.k]: e.target.value })} />}</label>)}<button>Guardar</button></form></Sheet>
    <div style={{ overflowX: "auto" }}><table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}><thead><tr>{p.cols.map(c => <th key={c.k} style={th}>{c.l}</th>)}<th style={th} /></tr></thead>
      <tbody>{rows.map((r, i) => <tr key={String(r.id ?? r.user_id ?? i)}>{p.cols.map(c => <td key={c.k} style={{ padding: "6px 8px", borderBottom: "1px solid #eee" }}>{fmt(r[c.k])}</td>)}
        <td style={{ whiteSpace: "nowrap" }}>{p.href && <Link href={p.href(r)}>Gestionar </Link>}{(p.actions ?? []).map(a => a.body(r) && <button key={a.l} onClick={() => act(r, a)} style={{ marginLeft: 4 }}>{a.l}</button>)}</td></tr>)}
        {rows.length === 0 && <tr><td colSpan={p.cols.length + 1} style={{ padding: 12, color: "#777" }}>Sin registros</td></tr>}</tbody></table></div></section>);
}
