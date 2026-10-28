"use client";
import { useState } from "react";
import { sb } from "@/lib/browser";
type D = { alerts: { alerta: string; n: number }[]; banks: { code: string; name: string; status: string }[]; audit: { id: number; action: string; entity: string; entity_id: string; at: string }[]; formats: { kind: string; version: number; prefix: string }[] };
export default function Admin() {
  const [d, setD] = useState<D | null>(null); const [msg, setMsg] = useState("");
  const login = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault(); const f = new FormData(e.currentTarget);
    const { data, error } = await sb().auth.signInWithPassword({ email: String(f.get("e")), password: String(f.get("p")) });
    if (error || !data.session) return setMsg(error?.message ?? "Error");
    const r = await fetch("/api/admin/overview", { headers: { authorization: `Bearer ${data.session.access_token}` } });
    r.ok ? setD(await r.json()) : setMsg((await r.json()).error);
  };
  const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
  return (<main style={{ maxWidth: 960, margin: "0 auto", padding: 24 }}><h1>Administración · Placeta One</h1>{msg && <p role="alert" style={{ color: "#a33" }}>{msg}</p>}
    {!d ? <form onSubmit={login} style={box}><input name="e" type="email" placeholder="Email" required /> <input name="p" type="password" placeholder="Contraseña" required /> <button>Entrar</button></form> : <>
      <section style={box}><h2>Alertas</h2>{d.alerts.map(a => <span key={a.alerta} style={{ marginRight: 16, color: a.n > 0 ? "#a33" : "#2a7" }}>{a.alerta.replaceAll("_", " ")}: <b>{a.n}</b></span>)}</section>
      <section style={box}><h2>Entidades</h2><table width="100%"><tbody>{d.banks.map(b => <tr key={b.code}><td>{b.code}</td><td>{b.name}</td><td>{b.status}</td></tr>)}</tbody></table></section>
      <section style={box}><h2>Numeración activa</h2>{d.formats.map(f => <code key={f.kind} style={{ marginRight: 12 }}>{f.prefix}… v{f.version}</code>)}</section>
      <section style={box}><h2>Auditoría reciente</h2><table width="100%"><tbody>{d.audit.map(a => <tr key={a.id}><td>{new Date(a.at).toLocaleString("es")}</td><td>{a.action}</td><td>{a.entity}</td><td style={{ fontFamily: "monospace" }}>{a.entity_id}</td></tr>)}</tbody></table></section></>}</main>);
}
