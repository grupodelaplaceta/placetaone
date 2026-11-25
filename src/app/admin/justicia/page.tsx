"use client";
import { useEffect, useState } from "react";
import { sb } from "@/lib/browser";
import { fechaHora } from "@/lib/fechas";

type Sancion = {
  id: string; tipo: string; estado: string; importe: number; motivo: string; norma: string;
  cuenta_iban: string | null; cuenta_origen_iban: string | null; destino_iban: string | null;
  denuncias: number; ejecucion_prevista: string | null; plazo_recurso_hasta: string | null;
  creada: string; bank_id: string; resolucion_recurso: string | null;
};
type Banco = { id: string; code: string; name: string };
type Fila = Record<string, unknown>;

const caja = { background: "#fff", border: "1px solid #ddd", borderRadius: 12, padding: 16, marginBottom: 16 } as const;
const campo = { padding: "6px 10px", borderRadius: 8, border: "1px solid #bbb" } as const;
const boton = { padding: "6px 14px", borderRadius: 8, border: "1px solid #0b6", background: "#0b6", color: "#fff", cursor: "pointer" } as const;
const botonSec = { padding: "6px 14px", borderRadius: 8, border: "1px solid #bbb", background: "#fff", cursor: "pointer" } as const;
const botonPeligro = { ...botonSec, borderColor: "#b00", color: "#b00" } as const;
const COLOR: Record<string, string> = { aprobada: "#0369a1", notificada: "#8a5a00", recurrida: "#7c3aed", firme: "#0b6", ejecutada: "#555", revocada: "#b00", anulada: "#888" };
const TIPO: Record<string, string> = { multa: "Multa", incautacion: "Incautación", embargo: "Embargo" };
const Chip = ({ t, c }: { t: string; c: string }) => <span style={{ background: c, color: "#fff", borderRadius: 10, padding: "2px 8px", fontSize: 12 }}>{t}</span>;

async function tok(): Promise<string> {
  const r = (await sb().auth.getSession()) as { data: { session: { access_token: string } | null } };
  return r.data.session?.access_token ?? "";
}
async function pide(ruta: string, metodo: "GET" | "POST", cuerpo?: unknown): Promise<{ ok: boolean; json: Fila }> {
  const r = await fetch(ruta, { method: metodo, headers: { authorization: `Bearer ${await tok()}`, "content-type": "application/json" }, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  return { ok: r.ok, json: (await r.json().catch(() => ({}))) as Fila };
}
async function lista(ruta: string): Promise<Fila[]> {
  const r = await fetch(ruta, { headers: { authorization: `Bearer ${await tok()}` } });
  const j: unknown = await r.json().catch(() => []);
  return Array.isArray(j) ? (j as Fila[]) : [];
}

function FilaSancion({ s, avisar, recargar }: { s: Sancion; avisar: (m: string) => void; recargar: () => void }) {
  const [fecha, setFecha] = useState("");
  const acto = async (ruta: string, cuerpo: unknown, ok: string) => {
    const r = await pide(ruta, "POST", cuerpo);
    avisar(r.ok ? ok : String(r.json.error ?? "No se pudo hacer"));
    recargar();
  };
  const revocar = () => {
    const motivo = prompt("Motivo de la revocación (mínimo 10 caracteres). Se deshacen los efectos ya cobrados o embargados.");
    if (!motivo) return;
    acto(`/api/admin/justicia/sanciones/${s.id}/revocar`, { motivo }, "Sanción revocada: sus efectos se han deshecho.");
  };
  const programar = () => {
    if (!fecha) return avisar("Elige la fecha y hora de ejecución");
    const cuando = new Date(fecha);
    if (cuando.getTime() < Date.now() + 5 * 3600e3) return avisar("La ejecución debe programarse con al menos 5 horas de antelación");
    acto(`/api/admin/justicia/sanciones/${s.id}/programar`, { fecha: cuando.toISOString() }, "Ejecución programada. El banco recibirá el aviso 5 horas antes.");
  };
  return (
    <tr style={{ borderBottom: "1px solid #eee", verticalAlign: "top" }}>
      <td style={{ whiteSpace: "nowrap" }}>{fechaHora(s.creada)}</td>
      <td><b>{TIPO[s.tipo] ?? s.tipo}</b><div style={{ fontSize: 12, color: "#666" }}>{s.norma}</div></td>
      <td style={{ fontSize: 12 }}>{s.cuenta_iban ?? "—"}{s.cuenta_origen_iban && <div style={{ color: "#7c3aed" }}>Junior · cobra el tutor (origen {s.cuenta_origen_iban})</div>}</td>
      <td>{Number(s.importe).toFixed(2)} Pz{s.destino_iban && <div style={{ fontSize: 12, color: "#666" }}>→ {s.destino_iban}</div>}</td>
      <td><Chip t={s.estado} c={COLOR[s.estado] ?? "#888"} /></td>
      <td style={{ fontSize: 12 }}>
        {s.plazo_recurso_hasta && <div>Denuncia hasta {fechaHora(s.plazo_recurso_hasta)}</div>}
        {s.ejecucion_prevista && <div>Ejecución {fechaHora(s.ejecucion_prevista)}</div>}
        <div>Denuncias: {s.denuncias}</div>
      </td>
      <td style={{ whiteSpace: "nowrap" }}>
        {s.estado === "aprobada" && <button style={boton} onClick={() => acto(`/api/admin/justicia/sanciones/${s.id}/notificar`, {}, "Notificada: se ha abierto el plazo para denunciar.")}>Notificar</button>}
        {s.estado === "recurrida" && <>
          <button style={boton} onClick={() => acto(`/api/admin/justicia/sanciones/${s.id}/resolver`, { confirmar: true }, "Recurso resuelto: la sanción queda firme.")}>Confirmar</button>{" "}
          <button style={botonSec} onClick={() => acto(`/api/admin/justicia/sanciones/${s.id}/resolver`, { confirmar: false }, "Recurso estimado: la sanción queda anulada.")}>Anular</button>
        </>}
        {s.estado === "firme" && <div style={{ marginBottom: 6 }}>
          <input type="datetime-local" value={fecha} onChange={(e) => setFecha(e.target.value)} style={campo} />{" "}
          <button style={botonSec} onClick={programar}>Programar</button>
        </div>}
        {s.estado === "ejecutada" && s.tipo === "embargo" && <button style={botonSec} onClick={() => acto(`/api/admin/justicia/sanciones/${s.id}/levantar`, {}, "Embargo levantado.")}>Levantar embargo</button>}
        {["notificada", "recurrida", "firme", "ejecutada"].includes(s.estado) && <div style={{ marginTop: 6 }}><button style={botonPeligro} onClick={revocar}>Revocar…</button></div>}
      </td>
    </tr>
  );
}


type Deuda = { id: string; ref?: string; account_id: string; principal: number; authorized_charges: number; paid: number; due_date: string | null; disputed: boolean };

function DeudasPanel() {
  const [deudas, setDeudas] = useState<Deuda[]>([]);
  const [msg2, setMsg2] = useState("");
  const cargar = async () => { setDeudas((await lista("/api/admin/r/debts")) as unknown as Deuda[]); };
  useEffect(() => { cargar(); }, []);
  const pendiente = (d: Deuda) => Number(d.principal) + Number(d.authorized_charges ?? 0) - Number(d.paid ?? 0);
  const actuar = async (d: Deuda, tipo: "anular" | "modificar") => {
    const justificacion = prompt("Justificación de la actuación (mínimo 30 caracteres):") ?? "";
    if (!justificacion) return;
    const referencia = prompt("Referencia del acuerdo de votación de esta actuación (se usa una sola vez):") ?? "";
    if (!referencia) return;
    let cuerpo: Record<string, unknown> = { justificacion, referencia };
    if (tipo === "modificar") {
      const nuevo = prompt(`Nuevo importe pendiente (ahora ${pendiente(d).toFixed(2)} Pz):`) ?? "";
      if (nuevo === "") return;
      cuerpo = { ...cuerpo, nuevo_pendiente: Number(nuevo) };
    }
    const r = await pide(`/api/admin/deudas/${d.id}/${tipo === "anular" ? "anular" : "modificar"}`, "POST", cuerpo);
    setMsg2(r.ok ? "Actuación registrada con su acuerdo." : String(r.json.error ?? "No se pudo hacer"));
    cargar();
  };
  const abiertas = deudas.filter((d) => pendiente(d) > 0);
  return (
    <section style={caja}>
      <h2 style={{ marginTop: 0, fontSize: 18 }}>Deudas: anular o modificar con acuerdo</h2>
      <p style={{ color: "#555", fontSize: 13 }}>Cada actuación exige una justificación y la referencia del acuerdo de votación de esa actuación concreta. Esa referencia solo puede usarse una vez.</p>
      {msg2 && <p role="alert">{msg2}</p>}
      <table width="100%" style={{ borderCollapse: "collapse", fontSize: 14 }}>
        <thead><tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}><th>Referencia</th><th>Cuenta</th><th>Pendiente</th><th>Pagado</th><th>Vence</th><th></th></tr></thead>
        <tbody>
          {abiertas.length === 0 && <tr><td colSpan={6} style={{ color: "#777", padding: 12 }}>No hay deudas con importe pendiente.</td></tr>}
          {abiertas.map((d) => (
            <tr key={d.id} style={{ borderBottom: "1px solid #eee" }}>
              <td>{String(d.ref ?? d.id).slice(0, 18)}</td>
              <td style={{ fontSize: 12 }}>{d.account_id}</td>
              <td>{pendiente(d).toFixed(2)} Pz{d.disputed && <span style={{ color: "#b00", fontSize: 12 }}> · en disputa</span>}</td>
              <td>{Number(d.paid ?? 0).toFixed(2)} Pz</td>
              <td>{d.due_date ?? "—"}</td>
              <td style={{ whiteSpace: "nowrap" }}>
                <button style={botonSec} onClick={() => actuar(d, "modificar")}>Modificar…</button>{" "}
                <button style={botonPeligro} onClick={() => actuar(d, "anular")}>Anular…</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

export default function Justicia() {
  const [lista_, setLista] = useState<Sancion[]>([]);
  const [bancos, setBancos] = useState<Banco[]>([]);
  const [msg, setMsg] = useState("");
  const [f, setF] = useState({ bank_id: "", tipo: "multa", iban: "", importe: "", motivo: "", norma: "", iban_destino: "" });

  const cargar = async () => {
    const r = await pide("/api/admin/justicia/sanciones", "GET");
    if (!r.ok) return setMsg(String(r.json.error ?? "No se pudieron cargar las sanciones"));
    setLista(((r.json.sanciones ?? []) as unknown) as Sancion[]);
  };
  useEffect(() => {
    cargar();
    lista("/api/admin/r/banks").then((b) => setBancos(b as unknown as Banco[]));
  }, []);

  const proponer = async () => {
    const r = await pide("/api/admin/justicia/sanciones", "POST", {
      bank_id: f.bank_id, tipo: f.tipo, iban: f.iban, importe: Number(f.importe), motivo: f.motivo, norma: f.norma,
      iban_destino: f.tipo === "embargo" ? null : f.iban_destino,
    });
    if (!r.ok) return setMsg(String(r.json.error ?? "No se pudo proponer"));
    setMsg("Sanción propuesta. Notifícala para abrir el plazo de denuncia.");
    setF({ ...f, iban: "", importe: "", motivo: "", norma: "", iban_destino: "" });
    cargar();
  };

  const conteo = (e: string) => lista_.filter((s) => s.estado === e).length;

  return (
    <>
      <h1>Sanciones</h1>
      <p style={{ color: "#555", maxWidth: 820 }}>
        Multas, incautaciones y embargos. Las propone y ejecuta la Junta sin doble aprobación. Cada ejecución se programa con al menos 5 horas de antelación: el banco recibe el aviso 5 horas antes.
        Para recurrir, la persona sancionada (o su tutor) debe presentar denuncia a través de su banco dentro del plazo. Un saldo de 160 Pz es inembargable.
      </p>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(150px, 1fr))", gap: 12, marginBottom: 16 }}>
        <div style={caja}><div style={{ color: "#777", fontSize: 12 }}>Notificadas</div><div style={{ fontSize: 22, fontWeight: 700 }}>{conteo("notificada")}</div></div>
        <div style={caja}><div style={{ color: "#777", fontSize: 12 }}>Recurridas</div><div style={{ fontSize: 22, fontWeight: 700 }}>{conteo("recurrida")}</div></div>
        <div style={caja}><div style={{ color: "#777", fontSize: 12 }}>Firmes sin programar</div><div style={{ fontSize: 22, fontWeight: 700 }}>{lista_.filter((s) => s.estado === "firme" && !s.ejecucion_prevista).length}</div></div>
        <div style={caja}><div style={{ color: "#777", fontSize: 12 }}>Ejecutadas</div><div style={{ fontSize: 22, fontWeight: 700 }}>{conteo("ejecutada")}</div></div>
      </div>

      {msg && <p role="alert" style={{ color: msg.includes("No se") || msg.includes("debe") ? "#b00" : "#0b6" }}>{msg}</p>}

      <section style={caja}>
        <h2 style={{ marginTop: 0, fontSize: 18 }}>Nueva sanción</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))", gap: 12 }}>
          <label>Entidad
            <select value={f.bank_id} onChange={(e) => setF({ ...f, bank_id: e.target.value })} style={{ ...campo, display: "block", width: "100%" }}>
              <option value="">— elige —</option>
              {bancos.map((b) => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}
            </select>
          </label>
          <label>Tipo
            <select value={f.tipo} onChange={(e) => setF({ ...f, tipo: e.target.value })} style={{ ...campo, display: "block", width: "100%" }}>
              <option value="multa">Multa</option><option value="incautacion">Incautación</option><option value="embargo">Embargo</option>
            </select>
          </label>
          <label>IBAN de la cuenta sancionada<input value={f.iban} onChange={(e) => setF({ ...f, iban: e.target.value })} placeholder="PZ-0000-0001" style={{ ...campo, display: "block", width: "100%" }} /></label>
          <label>Importe (Pz)<input type="number" value={f.importe} onChange={(e) => setF({ ...f, importe: e.target.value })} style={{ ...campo, display: "block", width: "100%" }} /></label>
          {f.tipo !== "embargo" && <label>Cuenta de destino (administración o tributos)<input value={f.iban_destino} onChange={(e) => setF({ ...f, iban_destino: e.target.value })} placeholder="PZ-0000-0001" style={{ ...campo, display: "block", width: "100%" }} /></label>}
          <label>Norma que la respalda<input value={f.norma} onChange={(e) => setF({ ...f, norma: e.target.value })} style={{ ...campo, display: "block", width: "100%" }} /></label>
        </div>
        <label style={{ display: "block", marginTop: 12 }}>Motivo (mínimo 20 caracteres)
          <textarea value={f.motivo} onChange={(e) => setF({ ...f, motivo: e.target.value })} rows={2} style={{ ...campo, display: "block", width: "100%" }} />
        </label>
        <button style={{ ...boton, marginTop: 12 }} onClick={proponer}>Proponer sanción</button>
      </section>

      <DeudasPanel />
      <div style={{ ...caja, overflowX: "auto" }}>
        <table width="100%" style={{ borderCollapse: "collapse", fontSize: 14 }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th>Fecha</th><th>Sanción</th><th>Cuenta</th><th>Importe</th><th>Estado</th><th>Plazos</th><th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            {lista_.length === 0 && <tr><td colSpan={7} style={{ color: "#777", padding: 12 }}>No hay sanciones.</td></tr>}
            {lista_.map((s) => <FilaSancion key={s.id} s={s} avisar={setMsg} recargar={cargar} />)}
          </tbody>
        </table>
      </div>
    </>
  );
}
