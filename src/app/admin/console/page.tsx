"use client";
import { useState } from "react";
import { sb } from "@/lib/browser";
// Plantillas de cada operación de Administración (el servidor añade p_actor y valida rol)
const T: Record<string, object> = {
  plone27_open_bank: { p_name: "Banco Nuevo" },
  plone27_open_account: { p_bank: "<uuid entidad>", p_kind: "personal", p_name: "Cuenta", p_owner: null },
  plone27_staff_set: { p_user: "<uuid usuario>", p_role: "financiero", p_active: true },
  plone27_numbering_propose: { p_kind: "REC", p_prefix: "PL27-REC-", p_year: true, p_width: 7, p_reason: "más capacidad" },
  plone27_numbering_simulate: { p_kind: "REC", p_version: 2 },
  plone27_numbering_publish: { p_kind: "REC", p_version: 2 },
  plone27_transfer_fee: { p_from: "<uuid>", p_to: "<uuid>", p_amount: 10, p_memo: "" },
  plone27_reverse: { p_tx: "<uuid>", p_reason: "error" },
  plone27_tax_issue: { p_code: "IGF", p_account: "<uuid>", p_base: 100, p_event_key: "evento-1", p_op: null, p_pathway: "recibo", p_due: "2026-12-31" },
  plone27_tax_pay_partial: { p_receipt: "<uuid>", p_amount: 5 },
  plone27_adjust_simulate: { p_receipt: "<uuid>", p_version: "<uuid>" },
  plone27_adjust_approve: { p_adj: "<uuid>" }, plone27_adjust_execute: { p_adj: "<uuid>" },
  plone27_issue_card: { p_account: "<uuid>", p_kind: "digital", p_design: null, p_limit: null, p_test: true },
  plone27_card_set_status: { p_card: "<uuid>", p_to: "blocked" },
  plone27_run_batch: { p_batch: "<uuid>" }, plone27_settle_bank: { p_bank: "<uuid>", p_from: "2026-10-01", p_to: "2026-10-31" },
  plone27_justify: { p_grant: "<uuid>", p_tx: "<uuid>", p_invoice: "F-1", p_amount: 10 }, plone27_reimburse: { p_just: "<uuid>" },
  plone27_approval_request: { p_subject: "bank", p_subject_id: "<uuid>", p_reason: "motivo" }, plone27_approval_decide: { p_id: "<uuid>", p_approve: true },
  plone27_cash_forecast: { p_days: 30 },
};
export default function Console() {
  const [tok, setTok] = useState(""); const [fn, setFn] = useState("plone27_open_bank"); const [body, setBody] = useState(JSON.stringify(T.plone27_open_bank, null, 2)); const [out, setOut] = useState("");
  const login = async (e: React.FormEvent<HTMLFormElement>) => { e.preventDefault(); const f = new FormData(e.currentTarget);
    const { data, error } = await sb().auth.signInWithPassword({ email: String(f.get("e")), password: String(f.get("p")) }); error ? setOut(error.message) : setTok(data.session!.access_token); };
  const run = async () => {
    let args; try { args = JSON.parse(body); } catch { return setOut("JSON inválido"); }
    if (!confirm(`Ejecutar ${fn}?`)) return;
    const r = await fetch(`/api/rpc/${fn}`, { method: "POST", headers: { authorization: `Bearer ${tok}`, "content-type": "application/json", "idempotency-key": crypto.randomUUID() }, body: JSON.stringify(args) });
    setOut(JSON.stringify(await r.json(), null, 2));
  };
  return (<main style={{ maxWidth: 800, margin: "0 auto", padding: 24 }}><h1>Consola de Administración</h1>
    {!tok ? <form onSubmit={login}><input name="e" type="email" placeholder="Email" required /> <input name="p" type="password" placeholder="Contraseña" required /> <button>Entrar</button></form> : <>
      <select value={fn} onChange={e => { setFn(e.target.value); setBody(JSON.stringify(T[e.target.value], null, 2)); }}>{Object.keys(T).map(k => <option key={k}>{k}</option>)}</select>
      <textarea value={body} onChange={e => setBody(e.target.value)} rows={10} style={{ width: "100%", fontFamily: "monospace", marginTop: 8 }} />
      <button onClick={run}>Ejecutar</button></>}
    <pre style={{ background: "#fff", padding: 12, overflow: "auto" }}>{out}</pre></main>);
}
