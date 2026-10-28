"use client";
import { useState } from "react";
import { sb } from "@/lib/browser";
type S = { key: string; category: string; description: string; vtype: string; allowed: string[] | null; min_v: number | null; max_v: number | null; value: unknown; sensitive: boolean; bank_overridable: boolean; version: number };
type C = { id: string; key: string; bank_id: string | null; new_value: unknown; old_value: unknown; reason: string };
export default function Settings() {
  const [tok, setTok] = useState(""); const [d, setD] = useState<{ settings: S[]; pending: C[]; banks: { id: string; code: string; name: string }[] } | null>(null); const [msg, setMsg] = useState("");
  const [bank, setBank] = useState("");
  const load = async (t = tok) => { const r = await fetch("/api/admin/settings", { headers: { authorization: `Bearer ${t}` } }); r.ok ? setD(await r.json()) : setMsg((await r.json()).error); };
  const call = async (fn: string, body: object) => { const r = await fetch(`/api/rpc/${fn}`, { method: "POST", headers: { authorization: `Bearer ${tok}`, "content-type": "application/json" }, body: JSON.stringify(body) });
    const j = await r.json(); setMsg(r.ok ? "Hecho" : j.error); if (r.ok) load(); };
  const login = async (e: React.FormEvent<HTMLFormElement>) => { e.preventDefault(); const f = new FormData(e.currentTarget);
    const { data, error } = await sb().auth.signInWithPassword({ email: String(f.get("e")), password: String(f.get("p")) });
    if (error || !data.session) return setMsg(error?.message ?? "Error"); setTok(data.session.access_token); load(data.session.access_token); };
  const edit = (s: S) => { const raw = prompt(`${s.key}\n${s.description}\nValor actual: ${JSON.stringify(s.value)}${s.allowed ? "\nPermitidos: " + s.allowed.join(", ") : ""}${s.min_v !== null ? `\nRango: ${s.min_v}–${s.max_v}` : ""}`); if (raw === null) return;
    const reason = prompt("Motivo (obligatorio)"); if (!reason) return;
    const v = s.vtype === "number" ? Number(raw) : s.vtype === "boolean" ? raw === "true" : raw;
    call("plone27_setting_propose", { p_key: s.key, p_value: v, p_bank: bank || null, p_reason: reason }); };
  const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
  return (<main style={{ maxWidth: 960, margin: "0 auto", padding: 24 }}><h1>Configuración</h1>{msg && <p role="alert">{msg}</p>}
    {!d ? <form onSubmit={login} style={box}><input name="e" type="email" placeholder="Email" required /> <input name="p" type="password" placeholder="Contraseña" required /> <button>Entrar</button></form> : <>
      {d.pending.length > 0 && <section style={box}><h2>Cambios pendientes de aprobación</h2>{d.pending.map(c => <div key={c.id}><code>{c.key}</code>: {JSON.stringify(c.old_value)} → <b>{JSON.stringify(c.new_value)}</b> — {c.reason}{" "}
        <button onClick={() => call("plone27_setting_approve", { p_change: c.id, p_approve: true })}>Aprobar</button> <button onClick={() => call("plone27_setting_approve", { p_change: c.id, p_approve: false })}>Rechazar</button></div>)}</section>}
      <section style={box}><label>Ámbito del cambio: <select value={bank} onChange={e => setBank(e.target.value)}><option value="">Global</option>{d.banks.map(b => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}</select></label></section>
      <section style={box}><table width="100%"><tbody>{d.settings.map(s => <tr key={s.key}><td>{s.category}</td><td><b>{s.key}</b><br /><small>{s.description}</small></td><td>{JSON.stringify(s.value)}</td><td>{s.sensitive ? "🔒 requiere 2ª persona" : ""}</td>
        <td><button disabled={!!bank && !s.bank_overridable} onClick={() => edit(s)}>Cambiar</button></td></tr>)}</tbody></table></section></>}</main>);
}
