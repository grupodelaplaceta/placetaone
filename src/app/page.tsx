"use client";
import { useState } from "react";
import { sb } from "@/lib/browser";

type Acc = { account_id: string; name: string; kind: string; status: string; booked: number; reserved: number };

export default function Home() {
  const [token, setToken] = useState(""); const [accs, setAccs] = useState<Acc[]>([]); const [msg, setMsg] = useState("");
  const [f, setF] = useState({ from: "", to: "", amount: "", memo: "" });
  const load = async (t = token) => {
    const r = await fetch("/api/accounts", { headers: { authorization: `Bearer ${t}` } });
    r.ok ? setAccs(await r.json()) : setMsg((await r.json()).error);
  };
  const login = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault(); const d = new FormData(e.currentTarget);
    const { data, error } = await sb().auth.signInWithPassword({ email: String(d.get("e")), password: String(d.get("p")) });
    if (error || !data.session) return setMsg(error?.message ?? "Error");
    setToken(data.session.access_token); setMsg(""); load(data.session.access_token);
  };
  const send = async (e: React.FormEvent) => {
    e.preventDefault();
    const r = await fetch("/api/transfers", { method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
      body: JSON.stringify({ ...f, amount: Number(f.amount) }) });
    const j = await r.json(); setMsg(r.ok ? `Contabilizada ${j.transaction_id}` : j.error); if (r.ok) load();
  };
  const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
  return (
    <main style={{ maxWidth: 880, margin: "0 auto", padding: 24 }}>
      <h1>Placeta One <small style={{ fontWeight: 400, color: "#777" }}>· importes en Pz</small></h1>
      {msg && <p role="alert" style={{ color: "#a33" }}>{msg}</p>}
      {!token ? (
        <form onSubmit={login} style={box}><input name="e" type="email" placeholder="Email" required /> <input name="p" type="password" placeholder="Contraseña" required /> <button>Entrar</button></form>
      ) : (<>
        <section style={box}><h2>Cuentas</h2>
          <table width="100%"><thead><tr style={{ textAlign: "left" }}><th>Cuenta</th><th>Tipo</th><th>Estado</th><th>Contable</th><th>Reservado</th><th>Disponible</th></tr></thead>
            <tbody>{accs.map(a => <tr key={a.account_id}><td>{a.name}</td><td>{a.kind}</td><td>{a.status}</td><td>{a.booked} Pz</td><td>{a.reserved} Pz</td><td><b>{a.booked - a.reserved} Pz</b></td></tr>)}</tbody></table></section>
        <form onSubmit={send} style={box}><h2>Nueva transferencia</h2>
          <select required onChange={e => setF({ ...f, from: e.target.value })}><option value="">Origen</option>{accs.map(a => <option key={a.account_id} value={a.account_id}>{a.name}</option>)}</select>{" "}
          <select required onChange={e => setF({ ...f, to: e.target.value })}><option value="">Destino</option>{accs.map(a => <option key={a.account_id} value={a.account_id}>{a.name}</option>)}</select>{" "}
          <input required type="number" step="0.01" min="0.01" placeholder="Pz" onChange={e => setF({ ...f, amount: e.target.value })} />{" "}
          <input placeholder="Concepto" onChange={e => setF({ ...f, memo: e.target.value })} /> <button>Enviar</button></form>
      </>)}
    </main>);
}
