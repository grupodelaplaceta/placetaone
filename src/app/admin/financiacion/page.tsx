"use client";
import { useEffect, useState } from "react";
import { sb } from "@/lib/browser";
import { Resource } from "../Resource";
import { fechaSolo } from "@/lib/fechas";

type Fila = Record<string, unknown>;
const caja = { background: "#fff", border: "1px solid #ddd", borderRadius: 12, padding: 16, marginBottom: 16 } as const;
const campo = { padding: "6px 10px", borderRadius: 8, border: "1px solid #bbb" } as const;
const boton = { padding: "6px 14px", borderRadius: 8, border: "1px solid #0b6", background: "#0b6", color: "#fff", cursor: "pointer" } as const;
const botonSec = { padding: "6px 14px", borderRadius: 8, border: "1px solid #bbb", background: "#fff", cursor: "pointer" } as const;
const A = { ref: "accounts", lab: ["iban", "name"] };

const PASOS = [
  { t: "1. Programa", d: "Marco de la ayuda: presupuesto y cuenta de fondos. Desde esa cuenta sale el dinero, y es donde se reserva." },
  { t: "2. Concesión", d: "Reserva el importe en la cuenta del programa. Si no hay fondos o se supera el presupuesto, no se crea. Un bono exige fecha de caducidad." },
  { t: "3. Justificación", d: "El beneficiario presenta un gasto de su propia cuenta. Se comprueba que sea elegible y que no supere lo concedido." },
  { t: "4. Abono", d: "Se paga el importe justificado y consume la reserva. Es el único paso que mueve dinero hacia el beneficiario." },
  { t: "5. Caducidad o reversión", d: "Lo no usado caduca y se libera. Un abono se puede revertir: si el beneficiario tiene saldo se revierte entero; si no, lo que falte queda como deuda que se cobra automáticamente." },
];

async function tok(): Promise<string> {
  const r = (await sb().auth.getSession()) as { data: { session: { access_token: string } | null } };
  return r.data.session?.access_token ?? "";
}
async function pide(ruta: string, metodo: "GET" | "POST", cuerpo?: unknown): Promise<{ ok: boolean; json: Record<string, unknown> }> {
  const t = await tok();
  const r = await fetch(ruta, { method: metodo, headers: { authorization: `Bearer ${t}`, "content-type": "application/json" }, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  const json = (await r.json().catch(() => ({}))) as Record<string, unknown>;
  return { ok: r.ok, json };
}
async function lista(ruta: string): Promise<Fila[]> {
  const t = await tok();
  const r = await fetch(ruta, { headers: { authorization: `Bearer ${t}` } });
  const j: unknown = await r.json().catch(() => []);
  return Array.isArray(j) ? (j as Fila[]) : [];
}
const COLOR: Record<string, string> = { activa: "#0b6", caducada: "#888", revertida: "#b00" };
const Chip = ({ t, c }: { t: string; c: string }) => <span style={{ background: c, color: "#fff", borderRadius: 10, padding: "2px 8px", fontSize: 12 }}>{t}</span>;

function Flujo() {
  const [i, setI] = useState(1);
  return (
    <div style={caja}>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 8, marginBottom: 12 }}>
        {PASOS.map((p, k) => (
          <button key={p.t} onClick={() => setI(k)} style={{ ...botonSec, textAlign: "left", background: k === i ? "#e6f7ef" : "#fff", borderColor: k === i ? "#0b6" : "#bbb" }}><b>{p.t}</b></button>
        ))}
      </div>
      <p style={{ margin: 0 }}>{PASOS[i].d}</p>
    </div>
  );
}

function Concesiones() {
  const [gs, setGs] = useState<Fila[]>([]);
  const [progs, setProgs] = useState<Fila[]>([]);
  const [cvs, setCvs] = useState<Fila[]>([]);
  const [accs, setAccs] = useState<Fila[]>([]);
  const [nueva, setNueva] = useState(false);
  const [msg, setMsg] = useState("");
  const [f, setF] = useState({ program: "", beneficiary: "", amount: "", convocatoria: "", caduca: "" });

  const cargar = async () => {
    setGs(await lista("/api/admin/r/grants"));
    setProgs(await lista("/api/admin/r/grantprograms"));
    setCvs(await lista("/api/admin/r/convocatorias"));
    setAccs(await lista("/api/admin/r/accounts"));
  };
  useEffect(() => { cargar(); }, []);

  const crear = async () => {
    const r = await pide("/api/admin/subvenciones", "POST", { program: f.program, beneficiary: f.beneficiary, amount: Number(f.amount), convocatoria: f.convocatoria || null, caduca: f.caduca || null });
    if (!r.ok) return setMsg(String(r.json.error ?? "No se pudo conceder"));
    setMsg("Concedida: el importe queda reservado en la cuenta del programa.");
    setNueva(false); setF({ program: "", beneficiary: "", amount: "", convocatoria: "", caduca: "" }); cargar();
  };

  const revertir = async (id: string) => {
    const motivo = prompt("Motivo de la reversión (mínimo 10 caracteres).\nSi el beneficiario tiene saldo, el abono se revierte entero. Si no, lo que falte queda como deuda.");
    if (!motivo) return;
    const r = await pide(`/api/admin/subvenciones/${id}/revertir`, "POST", { motivo });
    if (!r.ok) return setMsg(String(r.json.error ?? "No se pudo revertir"));
    setMsg(`Revertido: devuelto ${String(r.json.devuelto)} Pz, deuda ${String(r.json.deuda)} Pz.`);
    cargar();
  };

  const informe = async (id: string) => {
    const r = await fetch(`/api/admin/subvenciones/${id}/informe?formato=pdf`, { headers: { authorization: `Bearer ${await tok()}` } });
    if (!r.ok) return setMsg("No se pudo generar el informe");
    window.open(URL.createObjectURL(await r.blob()), "_blank");
  };

  const nombrePrograma = (id: unknown) => String(progs.find((p) => p.id === id)?.name ?? id);
  const nombreCuenta = (id: unknown) => { const a = accs.find((x) => x.id === id); return a ? `${String(a.name)} · ${String(a.iban)}` : String(id); };

  return (
    <section style={caja}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h2 style={{ margin: 0 }}>Concesiones</h2>
        <button style={boton} onClick={() => setNueva(!nueva)}>{nueva ? "Cerrar" : "+ Nueva concesión"}</button>
      </div>
      <p style={{ color: "#555" }}>Cada concesión reserva su importe. Lo pagado consume la reserva; lo no usado caduca y se libera.</p>
      {msg && <p role="alert">{msg}</p>}
      {nueva && (
        <div style={{ ...caja, background: "#f8fafc" }}>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 12 }}>
            <label>Programa
              <select value={f.program} onChange={(e) => setF({ ...f, program: e.target.value })} style={{ ...campo, display: "block", width: "100%" }}>
                <option value="">— elige —</option>
                {progs.map((p) => <option key={String(p.id)} value={String(p.id)}>{String(p.name)} ({String(p.kind)})</option>)}
              </select>
            </label>
            <label>Beneficiario
              <select value={f.beneficiary} onChange={(e) => setF({ ...f, beneficiary: e.target.value })} style={{ ...campo, display: "block", width: "100%" }}>
                <option value="">— elige —</option>
                {accs.map((a) => <option key={String(a.id)} value={String(a.id)}>{String(a.name)} · {String(a.iban)}</option>)}
              </select>
            </label>
            <label>Importe (Pz)<input type="number" value={f.amount} onChange={(e) => setF({ ...f, amount: e.target.value })} style={{ ...campo, display: "block", width: "100%" }} /></label>
            <label>Convocatoria (opcional)
              <select value={f.convocatoria} onChange={(e) => setF({ ...f, convocatoria: e.target.value })} style={{ ...campo, display: "block", width: "100%" }}>
                <option value="">Sin convocatoria</option>
                {cvs.map((c) => <option key={String(c.id)} value={String(c.id)}>{String(c.nombre)}</option>)}
              </select>
            </label>
            <label>Caduca (obligatoria en bonos)<input type="date" value={f.caduca} onChange={(e) => setF({ ...f, caduca: e.target.value })} style={{ ...campo, display: "block", width: "100%" }} /></label>
          </div>
          <button style={{ ...boton, marginTop: 12 }} onClick={crear}>Conceder y reservar</button>
        </div>
      )}
      <table width="100%" style={{ borderCollapse: "collapse" }}>
        <thead><tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}><th>Programa</th><th>Beneficiario</th><th>Pagado / concedido</th><th>Estado</th><th>Caduca</th><th></th></tr></thead>
        <tbody>
          {gs.length === 0 && <tr><td colSpan={6} style={{ color: "#777", padding: 12 }}>Todavía no hay concesiones.</td></tr>}
          {gs.map((g) => {
            const concedido = Number(g.granted ?? 0), pagado = Number(g.paid ?? 0);
            const pct = concedido > 0 ? Math.min(100, (pagado / concedido) * 100) : 0;
            const estado = String(g.estado ?? "activa");
            return (
              <tr key={String(g.id)} style={{ borderBottom: "1px solid #eee" }}>
                <td>{nombrePrograma(g.program_id)}</td>
                <td>{nombreCuenta(g.beneficiary_account)}</td>
                <td style={{ minWidth: 180 }}>
                  {pagado.toFixed(2)} / {concedido.toFixed(2)} Pz
                  <div style={{ background: "#eee", borderRadius: 6, height: 8 }}><div style={{ width: `${pct}%`, background: "#0b6", height: 8, borderRadius: 6 }} /></div>
                </td>
                <td><Chip t={estado} c={COLOR[estado] ?? "#888"} /></td>
                <td>{fechaSolo(g.caduca)}</td>
                <td style={{ whiteSpace: "nowrap" }}>
                  <button style={botonSec} onClick={() => informe(String(g.id))}>Informe PDF</button>{" "}
                  {estado !== "revertida" && <button style={botonSec} onClick={() => revertir(String(g.id))}>Revertir…</button>}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </section>
  );
}

function FilaConvocatoria({ c, avisar, recargar }: { c: Fila; avisar: (m: string) => void; recargar: () => void }) {
  const [caduca, setCaduca] = useState(String(c.caduca ?? ""));
  const guardarCaducidad = async () => {
    const r = await pide(`/api/admin/convocatorias/${String(c.id)}/caducidad`, "POST", { caduca: caduca || null });
    avisar(r.ok ? "Caducidad guardada: aplica a los bonos nuevos de esta convocatoria." : String(r.json.error ?? "Error"));
    recargar();
  };
  const cambiarReautorizacion = async (valor: boolean) => {
    const r = await pide(`/api/admin/convocatorias/${String(c.id)}/reautorizacion`, "POST", { reautoriza_recuperados: valor });
    avisar(r.ok ? "Opción guardada." : String(r.json.error ?? "Error"));
    recargar();
  };
  const abierta = String(c.estado) === "abierta";
  return (
    <tr style={{ borderBottom: "1px solid #eee" }}>
      <td>{String(c.nombre)}</td>
      <td>{fechaSolo(c.desde)} – {fechaSolo(c.hasta)}</td>
      <td><Chip t={abierta ? "abierta" : "cerrada"} c={abierta ? "#0b6" : "#888"} /></td>
      <td>
        <input type="date" value={caduca} onChange={(e) => setCaduca(e.target.value)} style={campo} />{" "}
        <button style={botonSec} onClick={guardarCaducidad}>Guardar</button>
      </td>
      <td>
        <label><input type="checkbox" checked={Boolean(c.reautoriza_recuperados)} onChange={(e) => cambiarReautorizacion(e.target.checked)} /> reautorizar lo recuperado</label>
      </td>
    </tr>
  );
}

function Convocatorias() {
  const [cvs, setCvs] = useState<Fila[]>([]);
  const [msg, setMsg] = useState("");
  const cargar = async () => setCvs(await lista("/api/admin/r/convocatorias"));
  useEffect(() => { cargar(); }, []);
  return (
    <section style={caja}>
      <h2 style={{ marginTop: 0 }}>Convocatorias</h2>
      <p style={{ color: "#555" }}>Cada convocatoria decide la caducidad de sus bonos y si lo recuperado de una deuda se vuelve a autorizar. Lo recuperado solo se reautoriza si la convocatoria está abierta y lo permite.</p>
      {msg && <p role="alert">{msg}</p>}
      <table width="100%" style={{ borderCollapse: "collapse" }}>
        <thead><tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}><th>Nombre</th><th>Vigencia</th><th>Estado</th><th>Caducidad de bonos</th><th>Recuperados</th></tr></thead>
        <tbody>
          {cvs.length === 0 && <tr><td colSpan={5} style={{ color: "#777", padding: 12 }}>No hay convocatorias.</td></tr>}
          {cvs.map((c) => <FilaConvocatoria key={String(c.id)} c={c} avisar={setMsg} recargar={cargar} />)}
        </tbody>
      </table>
    </section>
  );
}

export default function Financiacion() {
  return (
    <>
      <h1>Subvenciones, bonos y tesorería</h1>
      <Flujo />
      <details open style={{ background: "#f8fafc", border: "1px solid #cbd5e1", borderRadius: 10, padding: 16, marginBottom: 16 }}>
        <summary style={{ fontWeight: 700, cursor: "pointer" }}>Cómo funciona (léelo antes de conceder nada)</summary>
        <ul style={{ lineHeight: 1.7 }}>
          <li><b>Reserva.</b> Conceder reserva el importe en la cuenta del programa. Nadie puede conceder por encima del presupuesto ni sin fondos.</li>
          <li><b>Justificación.</b> El beneficiario presenta un gasto de su cuenta. El sistema comprueba que sea elegible y que no supere lo concedido.</li>
          <li><b>Abono.</b> «Aprobar y pagar» transfiere al beneficiario y consume la reserva. Sin reserva suficiente, no se paga.</li>
          <li><b>Caducidad.</b> Lo no pagado caduca y se libera. Un bono exige fecha de caducidad (por convocatoria o explícita).</li>
          <li><b>Reversión.</b> Revertir un abono devuelve el dinero si el beneficiario tiene saldo. Si no lo tiene, lo disponible vuelve y el resto queda como deuda que se cobra automáticamente. La deuda cobrada se reautoriza si la convocatoria lo permite.</li>
          <li><b>Quién puede.</b> En este panel opera la Junta. Las entidades operan sus programas por su API de banca.</li>
        </ul>
      </details>
      <Concesiones />
      <Convocatorias />
      <Resource res="grantprograms" title="Programas" cols={[{ k: "name", l: "Nombre" }, { k: "kind", l: "Tipo" }, { k: "budget", l: "Presupuesto" }, { k: "funding_account", l: "Cuenta de fondos" }]}
        create={[{ k: "name", l: "Nombre" }, { k: "kind", l: "Tipo", t: "select", o: ["subvencion", "bono"] }, { k: "budget", l: "Presupuesto", t: "number" }, { k: "funding_account", l: "Cuenta de fondos", ...A }]} />
      <Resource res="justifications" title="Justificaciones y abonos" cols={[{ k: "ref", l: "Ref" }, { k: "invoice_ref", l: "Factura" }, { k: "amount", l: "Pz" }, { k: "status", l: "Estado" }, { k: "reimb_ref", l: "Abono" }]}
        create={[{ k: "grant_id", l: "Concesión", ref: "grants", lab: ["ref", "granted"] }, { k: "transaction_id", l: "Transacción", ref: "transactions", lab: ["ref", "memo"] }, { k: "invoice_ref", l: "Nº factura" }, { k: "amount", l: "Importe", t: "number" }]}
        actions={[{ l: "Aprobar y pagar", body: (r) => r.status === "pending" || r.status === "approved" ? { reimburse: true } : null }, { l: "Rechazar", body: (r) => r.status === "pending" ? { status: "rejected" } : null }]} />
      <Resource res="budgets" title="Presupuestos y fondos restringidos" cols={[{ k: "name", l: "Nombre" }, { k: "period", l: "Periodo" }, { k: "approved", l: "Aprobado" }, { k: "committed", l: "Comprometido" }, { k: "executed", l: "Ejecutado" }, { k: "restricted", l: "Restringido" }]}
        create={[{ k: "name", l: "Nombre" }, { k: "period", l: "Periodo ([2026-01-01,2026-12-31])" }, { k: "approved", l: "Aprobado", t: "number" }, { k: "restricted", l: "Fondo restringido", t: "bool" }]} />
      <Resource res="debts" title="Deudas por reversión y otras" cols={[{ k: "ref", l: "Ref" }, { k: "account_id", l: "Deudor" }, { k: "principal", l: "Principal" }, { k: "paid", l: "Pagado" }, { k: "due_date", l: "Vence" }, { k: "disputed", l: "Disputa" }]}
        create={[{ k: "account_id", l: "Deudor", ...A }, { k: "creditor_account", l: "Acreedor", ...A }, { k: "principal", l: "Principal", t: "number" }, { k: "due_date", l: "Vencimiento", t: "date" }, { k: "reason", l: "Origen autorizado" }]}
        actions={[{ l: "Abrir disputa…", prompt: "Motivo de la disputa", body: (r, v) => !r.disputed ? { dispute: v } : null }]} />
    </>
  );
}
