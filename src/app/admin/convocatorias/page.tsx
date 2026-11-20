"use client";
import { useEffect, useState } from "react";
import { sb } from "@/lib/browser";
import { fechaSolo } from "@/lib/fechas";

type Concesion = { id: string; beneficiario: string | null; granted: number; paid: number; estado: string; caduca: string | null };
type Conv = {
  id: string; nombre: string; tipo: string; importe: number; desde: string; hasta: string; caduca: string | null;
  estado: string; dirigida_a: string; cuenta_iban: string | null; reautoriza_recuperados: boolean;
  entidad_nombre: string | null; empresa: { id: string; nombre: string } | null; destino_nombre: string | null;
  concedido: number; pagado: number; concesiones: Concesion[];
};

const caja = { background: "#fff", border: "1px solid #ddd", borderRadius: 12, padding: 16, marginBottom: 16 } as const;
const campo = { padding: "6px 10px", borderRadius: 8, border: "1px solid #bbb" } as const;
const boton = { padding: "6px 14px", borderRadius: 8, border: "1px solid #0b6", background: "#0b6", color: "#fff", cursor: "pointer" } as const;
const botonSec = { padding: "6px 14px", borderRadius: 8, border: "1px solid #bbb", background: "#fff", cursor: "pointer" } as const;
const COLOR: Record<string, string> = { abierta: "#0b6", cerrada: "#888", activa: "#0b6", caducada: "#888", revertida: "#b00" };
const Chip = ({ t, c }: { t: string; c: string }) => <span style={{ background: c, color: "#fff", borderRadius: 10, padding: "2px 8px", fontSize: 12 }}>{t}</span>;

async function tok(): Promise<string> {
  const r = (await sb().auth.getSession()) as { data: { session: { access_token: string } | null } };
  return r.data.session?.access_token ?? "";
}
async function pide(ruta: string, metodo: "GET" | "POST", cuerpo?: unknown): Promise<{ ok: boolean; json: Record<string, unknown> }> {
  const r = await fetch(ruta, { method: metodo, headers: { authorization: `Bearer ${await tok()}`, "content-type": "application/json" }, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) });
  return { ok: r.ok, json: (await r.json().catch(() => ({}))) as Record<string, unknown> };
}

function Fila({ c, avisar, recargar }: { c: Conv; avisar: (m: string) => void; recargar: () => void }) {
  const [verConc, setVerConc] = useState(false);
  const [caduca, setCaduca] = useState(c.caduca ?? "");
  const pct = c.importe > 0 ? Math.min(100, (c.concedido / c.importe) * 100) : 0;

  const cerrar = async () => {
    if (!confirm(`¿Cerrar «${c.nombre}»? No admitirá concesiones nuevas. Lo ya concedido sigue su curso.`)) return;
    const r = await pide(`/api/admin/convocatorias/${c.id}/cerrar`, "POST");
    avisar(r.ok ? "Convocatoria cerrada." : String(r.json.error ?? "No se pudo cerrar"));
    recargar();
  };
  const guardarCaducidad = async () => {
    const r = await pide(`/api/admin/convocatorias/${c.id}/caducidad`, "POST", { caduca: caduca || null });
    avisar(r.ok ? "Caducidad guardada: aplica a las concesiones nuevas." : String(r.json.error ?? "Error"));
    recargar();
  };
  const reautorizacion = async (valor: boolean) => {
    const r = await pide(`/api/admin/convocatorias/${c.id}/reautorizacion`, "POST", { reautoriza_recuperados: valor });
    avisar(r.ok ? "Opción guardada." : String(r.json.error ?? "Error"));
    recargar();
  };

  return (
    <>
      <tr style={{ borderBottom: "1px solid #eee", verticalAlign: "top" }}>
        <td><b>{c.nombre}</b><div style={{ color: "#777", fontSize: 12 }}>{c.entidad_nombre ?? "—"}</div></td>
        <td><Chip t={c.tipo} c={c.tipo === "bono" ? "#7c3aed" : "#0369a1"} /></td>
        <td>{c.empresa?.nombre ?? "—"}</td>
        <td>{c.dirigida_a === "todos" ? "Toda la entidad" : <>Solo <b>{c.destino_nombre ?? "una empresa"}</b></>}</td>
        <td style={{ fontSize: 12 }}>{c.cuenta_iban ?? "—"}</td>
        <td style={{ whiteSpace: "nowrap" }}>{fechaSolo(c.desde)} – {fechaSolo(c.hasta)}</td>
        <td style={{ minWidth: 170 }}>
          {c.concedido.toFixed(2)} / {c.importe.toFixed(2)} Pz
          <div style={{ background: "#eee", borderRadius: 6, height: 8 }}><div style={{ width: `${pct}%`, background: "#0b6", height: 8, borderRadius: 6 }} /></div>
          <div style={{ fontSize: 12, color: "#555" }}>pagado {c.pagado.toFixed(2)} Pz</div>
        </td>
        <td><Chip t={c.estado} c={COLOR[c.estado] ?? "#888"} /></td>
        <td>
          <input type="date" value={caduca} onChange={(e) => setCaduca(e.target.value)} style={campo} />{" "}
          <button style={botonSec} onClick={guardarCaducidad}>Guardar</button>
          <div style={{ fontSize: 11, color: "#777" }}>Solo para bonos nuevos</div>
        </td>
        <td>
          <label><input type="checkbox" checked={c.reautoriza_recuperados} onChange={(e) => reautorizacion(e.target.checked)} /> reautorizar lo recuperado</label>
        </td>
        <td style={{ whiteSpace: "nowrap" }}>
          {c.estado === "abierta" && <button style={botonSec} onClick={cerrar}>Cerrar</button>}{" "}
          <button style={botonSec} onClick={() => setVerConc(!verConc)}>{verConc ? "Ocultar" : `Concesiones (${c.concesiones.length})`}</button>
        </td>
      </tr>
      {verConc && (
        <tr><td colSpan={11} style={{ background: "#f8fafc", padding: 12 }}>
          {c.concesiones.length === 0 && <span style={{ color: "#777" }}>Todavía no hay concesiones.</span>}
          {c.concesiones.length > 0 && (
            <table width="100%" style={{ borderCollapse: "collapse" }}>
              <thead><tr style={{ textAlign: "left" }}><th>Beneficiario (IBAN)</th><th>Concedido</th><th>Pagado</th><th>Estado</th><th>Caduca</th></tr></thead>
              <tbody>
                {c.concesiones.map((g) => (
                  <tr key={g.id}><td style={{ fontSize: 12 }}>{g.beneficiario ?? "—"}</td><td>{g.granted.toFixed(2)} Pz</td><td>{g.paid.toFixed(2)} Pz</td><td><Chip t={g.estado} c={COLOR[g.estado] ?? "#888"} /></td><td>{fechaSolo(g.caduca)}</td></tr>
                ))}
              </tbody>
            </table>
          )}
        </td></tr>
      )}
    </>
  );
}

export default function ConvocatoriasEmpresa() {
  const [lista, setLista] = useState<Conv[]>([]);
  const [msg, setMsg] = useState("");
  const [estado, setEstado] = useState<"todas" | "abierta" | "cerrada">("todas");
  const [origen, setOrigen] = useState<"empresas" | "todas">("empresas");

  const cargar = async () => {
    const r = await pide("/api/admin/convocatorias/resumen", "GET");
    if (!r.ok) return setMsg(String(r.json.error ?? "No se pudo cargar"));
    setLista(((r.json.convocatorias ?? []) as unknown) as Conv[]);
  };
  useEffect(() => { cargar(); }, []);

  const visibles = lista.filter((c) => (origen === "todas" || c.empresa !== null) && (estado === "todas" || c.estado === estado));
  const abiertas = lista.filter((c) => c.estado === "abierta" && c.empresa !== null).length;
  const concedido = lista.filter((c) => c.empresa !== null).reduce((n, c) => n + c.concedido, 0);
  const pagado = lista.filter((c) => c.empresa !== null).reduce((n, c) => n + c.pagado, 0);

  return (
    <>
      <h1>Convocatorias de empresa</h1>
      <p style={{ color: "#555", maxWidth: 800 }}>
        Aquí ves todas las convocatorias de subvención y bono que abren las empresas, con su destino, su cuenta de fondos y lo concedido. Desde aquí puedes cerrarlas, fijar la caducidad de sus bonos y decidir si lo recuperado de una deuda se vuelve a autorizar.
      </p>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(180px, 1fr))", gap: 12, marginBottom: 16 }}>
        <div style={caja}><div style={{ color: "#777", fontSize: 12 }}>Abiertas</div><div style={{ fontSize: 24, fontWeight: 700 }}>{abiertas}</div></div>
        <div style={caja}><div style={{ color: "#777", fontSize: 12 }}>Concedido (empresas)</div><div style={{ fontSize: 24, fontWeight: 700 }}>{concedido.toFixed(2)} Pz</div></div>
        <div style={caja}><div style={{ color: "#777", fontSize: 12 }}>Pagado (empresas)</div><div style={{ fontSize: 24, fontWeight: 700 }}>{pagado.toFixed(2)} Pz</div></div>
      </div>

      <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "center", marginBottom: 12 }}>
        <label>Estado: <select value={estado} onChange={(e) => setEstado(e.target.value as "todas" | "abierta" | "cerrada")} style={campo}>
          <option value="todas">Todas</option><option value="abierta">Abiertas</option><option value="cerrada">Cerradas</option>
        </select></label>
        <label>Origen: <select value={origen} onChange={(e) => setOrigen(e.target.value as "empresas" | "todas")} style={campo}>
          <option value="empresas">Solo empresas</option><option value="todas">Todas</option>
        </select></label>
        <button style={botonSec} onClick={cargar}>Actualizar</button>
      </div>

      {msg && <p role="alert" style={{ color: "#b00" }}>{msg}</p>}

      <div style={{ ...caja, overflowX: "auto" }}>
        <table width="100%" style={{ borderCollapse: "collapse", fontSize: 14 }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th>Convocatoria</th><th>Tipo</th><th>Empresa</th><th>Destino</th><th>Cuenta de fondos</th><th>Vigencia</th><th>Concedido</th><th>Estado</th><th>Caducidad de bonos</th><th>Recuperados</th><th></th>
            </tr>
          </thead>
          <tbody>
            {visibles.length === 0 && <tr><td colSpan={11} style={{ color: "#777", padding: 12 }}>No hay convocatorias con estos filtros.</td></tr>}
            {visibles.map((c) => <Fila key={c.id} c={c} avisar={setMsg} recargar={cargar} />)}
          </tbody>
        </table>
      </div>
    </>
  );
}
