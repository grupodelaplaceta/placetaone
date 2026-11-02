"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Cuenta institucional: presupuestos, gastos, tareas, nóminas, fondos, recurrentes, convocatorias, solicitudes y configuración.
// Cada operación se aplica como la persona indicada en «Actuar como (DIP)»: se respetan sus permisos reales.
type Ent = { account_id: string; cip: string; nombre: string; activa: boolean; solicitudes_activas: boolean; doble_firma_desde: number | null; presupuesto_anual: number };
type Fila = Record<string, any>;
type Datos = { entidad?: Ent; unidades: Fila[]; presupuestos: Fila[]; meses: Fila[]; planes: Fila[]; fondos: Fila[]; gastos: Fila[]; tareas: Fila[]; recurrentes: Fila[]; convocatorias: Fila[]; solicitudes: Fila[] };

const TABS = ["Presupuestos", "Gastos", "Tareas", "Nóminas", "Fondos y recurrentes", "Convocatorias y solicitudes", "Configuración"];
const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;

function Sel({ valor, onCambio, opciones, vacio }: { valor: string; onCambio: (v: string) => void; opciones: [string, string][]; vacio: string }) {
  return (
    <select style={campo} value={valor} onChange={(e) => onCambio(e.target.value)}>
      <option value="">{vacio}</option>
      {opciones.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
    </select>
  );
}

export default function Institucional() {
  const [entidades, setEntidades] = useState<Ent[]>([]);
  const [cip, setCip] = useState("");
  const [datos, setDatos] = useState<Datos | null>(null);
  const [tab, setTab] = useState(TABS[0]);
  const [dipActor, setDipActor] = useState("");
  const [f, setF] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState("");
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));

  const cargarEntidades = () => api("/api/admin/institucional").then((r: { entidades: Ent[] }) => setEntidades(r.entidades ?? [])).catch((e) => setMsg((e as Error).message));
  const cargar = (c: string) => {
    if (!c) { setDatos(null); return; }
    api(`/api/admin/institucional?cip=${encodeURIComponent(c)}`).then((r: Datos) => setDatos(r)).catch((e) => setMsg((e as Error).message));
  };
  useEffect(() => { cargarEntidades(); }, []);
  useEffect(() => { cargar(cip); }, [cip]);

  const accion = async (cuerpo: Record<string, unknown>, ok: string) => {
    if (!dipActor) { setMsg("Indica el DIP de la persona que actúa."); return; }
    try {
      const r = await api("/api/admin/institucional", "POST", { cip, dip_actor: dipActor, ...cuerpo });
      const extra = r && r.resultado !== undefined && r.resultado !== null ? ` (${String(r.resultado)})` : "";
      setMsg(ok + extra);
      cargar(cip);
    } catch (e) { setMsg((e as Error).message); }
  };

  const unidades = datos?.unidades ?? [];
  const nombreUnidad = (id: string) => unidades.find((u) => u.id === id)?.nombre ?? id;
  const opcionesUnidades: [string, string][] = unidades.map((u) => [u.id, `${u.nombre} (${u.tipo})`]);
  const gastosPorAprobar = (datos?.gastos ?? []).filter((g) => g.estado === "propuesto" || g.estado === "aprobado");

  return (
    <>
      <h1>Cuenta institucional</h1>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center", marginBottom: 10 }}>
        <Sel valor={cip} onCambio={setCip} opciones={entidades.map((e): [string, string] => [e.cip, `${e.nombre} · ${e.cip}`])} vacio="Elige una entidad…" />
        <input style={{ ...campo, minWidth: 240 }} placeholder="Actuar como (DIP de la persona)" value={dipActor} onChange={(e) => setDipActor(e.target.value)} />
        <span className="muted">Las operaciones usan los permisos reales de esa persona.</span>
      </div>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      {!datos && <p className="muted">Elige una entidad para empezar.</p>}
      {datos && (
        <>
          <div role="tablist" style={{ display: "flex", gap: 6, flexWrap: "wrap", borderBottom: "1px solid #e2e8f0", marginBottom: 12 }}>
            {TABS.map((t) => (
              <button key={t} role="tab" aria-selected={tab === t} onClick={() => setTab(t)}
                style={{ padding: "8px 12px", border: 0, borderBottom: tab === t ? "3px solid #1d4ed8" : "3px solid transparent", background: "none", fontWeight: tab === t ? 700 : 500, cursor: "pointer" }}>{t}</button>
            ))}
          </div>

          {tab === "Presupuestos" && (
            <>
              <Card titulo="Presupuestos anuales por unidad">
                <table style={{ width: "100%", fontSize: 14 }}>
                  <thead><tr><th align="left">Unidad</th><th align="left">Ejercicio</th><th align="right">Anual (Pz)</th><th align="right">Reparto mensual (Pz)</th></tr></thead>
                  <tbody>
                    {datos.presupuestos.map((p) => (
                      <tr key={p.unidad + p.ejercicio}>
                        <td>{nombreUnidad(p.unidad)}</td><td>{p.ejercicio}</td><td align="right">{Number(p.anual).toLocaleString("es-ES")}</td>
                        <td align="right">{datos.meses.filter((m) => m.unidad === p.unidad && m.ejercicio === p.ejercicio).reduce((a, m) => a + Number(m.importe), 0).toLocaleString("es-ES")}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <p className="muted">General de la entidad: {Number(datos.entidad?.presupuesto_anual ?? 0).toLocaleString("es-ES")} Pz</p>
              </Card>
              <Card titulo="Fijar presupuesto anual">
                <Sel valor={f.pu ?? ""} onCambio={(v) => set("pu", v)} opciones={opcionesUnidades} vacio="Unidad…" />
                <input style={{ ...campo, width: 100 }} type="number" placeholder="Ejercicio" value={f.pe ?? ""} onChange={(e) => set("pe", e.target.value)} />
                <input style={{ ...campo, width: 140 }} type="number" placeholder="Importe Pz" value={f.pi ?? ""} onChange={(e) => set("pi", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "presupuesto_anual", unidad: f.pu, ejercicio: Number(f.pe), importe: Number(f.pi) }, "Presupuesto fijado.")}>Fijar</button>
              </Card>
              <Card titulo="Presupuesto general de la entidad">
                <input style={{ ...campo, width: 160 }} type="number" placeholder="Importe Pz" value={f.gi ?? ""} onChange={(e) => set("gi", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "presupuesto_general", importe: Number(f.gi) }, "Presupuesto general fijado.")}>Fijar general</button>
              </Card>
              <Card titulo="Reparto mensual (opcional)">
                <Sel valor={f.mu ?? ""} onCambio={(v) => set("mu", v)} opciones={opcionesUnidades} vacio="Unidad…" />
                <input style={{ ...campo, width: 100 }} type="number" placeholder="Ejercicio" value={f.me ?? ""} onChange={(e) => set("me", e.target.value)} />
                <input style={{ ...campo, width: 80 }} type="number" min={1} max={12} placeholder="Mes" value={f.mm ?? ""} onChange={(e) => set("mm", e.target.value)} />
                <input style={{ ...campo, width: 140 }} type="number" placeholder="Importe Pz" value={f.mi ?? ""} onChange={(e) => set("mi", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "presupuesto_mes", unidad: f.mu, ejercicio: Number(f.me), mes: Number(f.mm), importe: Number(f.mi) }, "Mes fijado.")}>Fijar mes</button>
                <p className="muted">El reparto mensual no puede superar el anual de la unidad.</p>
              </Card>
              <Card titulo="Planes plurianuales">
                <ul>{datos.planes.map((p) => <li key={p.id}>{p.nombre} · {p.ejercicio_inicio}–{p.ejercicio_fin} · total {Number(p.total).toLocaleString("es-ES")} Pz · {nombreUnidad(p.unidad)}</li>)}</ul>
                <Sel valor={f.plu ?? ""} onCambio={(v) => set("plu", v)} opciones={opcionesUnidades} vacio="Unidad…" />
                <input style={campo} placeholder="Nombre del plan" value={f.pln ?? ""} onChange={(e) => set("pln", e.target.value)} />
                <input style={{ ...campo, width: 100 }} type="number" placeholder="Desde" value={f.pli ?? ""} onChange={(e) => set("pli", e.target.value)} />
                <input style={{ ...campo, width: 100 }} type="number" placeholder="Hasta" value={f.plf ?? ""} onChange={(e) => set("plf", e.target.value)} />
                <input style={{ ...campo, width: 140 }} type="number" placeholder="Total Pz" value={f.plt ?? ""} onChange={(e) => set("plt", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "plan_plurianual", unidad: f.plu, nombre: f.pln, inicio: Number(f.pli), fin: Number(f.plf), total: Number(f.plt) }, "Plan creado.")}>Crear plan</button>
              </Card>
            </>
          )}

          {tab === "Gastos" && (
            <>
              <Card titulo="Gastos">
                <table style={{ width: "100%", fontSize: 14 }}>
                  <thead><tr><th align="left">Fecha</th><th align="left">Unidad</th><th align="left">Concepto</th><th align="right">Importe</th><th align="left">Origen</th><th align="left">Estado</th><th /></tr></thead>
                  <tbody>
                    {datos.gastos.map((g) => (
                      <tr key={g.id}>
                        <td>{g.fecha}</td><td>{nombreUnidad(g.unidad)}</td><td>{g.concepto}</td>
                        <td align="right">{Number(g.importe).toLocaleString("es-ES")}</td><td>{g.origen}</td>
                        <td><Badge tono={g.estado === "pagado" ? "ok" : g.estado === "rechazado" ? "bad" : "neutral"}>{g.estado}</Badge></td>
                        <td>
                          {g.estado === "propuesto" && <button className="btn" onClick={() => accion({ accion: "gasto_aprobar", gasto: g.id }, "Gasto aprobado o pendiente de segunda firma.")}>Aprobar</button>}
                          {g.estado === "aprobado" && <button className="btn btn-primary" onClick={() => accion({ accion: "gasto_pagar", gasto: g.id }, "Pago ejecutado.")}>Pagar</button>}
                          {(g.estado === "propuesto" || g.estado === "aprobado") && <button className="btn" onClick={() => { const m = window.prompt("Motivo del rechazo (mínimo 5 caracteres)") ?? ""; if (m.length >= 5) accion({ accion: "gasto_rechazar", gasto: g.id, motivo: m }, "Gasto rechazado."); }}>Rechazar</button>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <p className="muted">Pendientes de decisión: {gastosPorAprobar.length}</p>
              </Card>
              <Card titulo="Proponer gasto">
                <Sel valor={f.gu ?? ""} onCambio={(v) => set("gu", v)} opciones={opcionesUnidades} vacio="Unidad…" />
                <input style={{ ...campo, width: 100 }} type="number" placeholder="Ejercicio" value={f.ge ?? ""} onChange={(e) => set("ge", e.target.value)} />
                <input style={{ ...campo, width: 120 }} type="number" placeholder="Importe" value={f.gi2 ?? ""} onChange={(e) => set("gi2", e.target.value)} />
                <input style={{ ...campo, minWidth: 220 }} placeholder="Concepto" value={f.gc ?? ""} onChange={(e) => set("gc", e.target.value)} />
                <input style={{ ...campo, minWidth: 180 }} placeholder="IBAN beneficiario" value={f.gib ?? ""} onChange={(e) => set("gib", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "gasto_proponer", unidad: f.gu, ejercicio: Number(f.ge), importe: Number(f.gi2), concepto: f.gc, iban: f.gib }, "Gasto propuesto.")}>Proponer</button>
              </Card>
              <Card titulo="Asignar fondo restringido a un gasto propuesto">
                <input style={{ ...campo, minWidth: 260 }} placeholder="Identificador del gasto" value={f.fg ?? ""} onChange={(e) => set("fg", e.target.value)} />
                <Sel valor={f.ff ?? ""} onCambio={(v) => set("ff", v)} opciones={datos.fondos.map((x): [string, string] => [x.id, x.nombre])} vacio="Fondo…" />
                <button className="btn" onClick={() => accion({ accion: "gasto_fondo", gasto: f.fg, fondo: f.ff }, "Fondo asignado.")}>Asignar</button>
              </Card>
            </>
          )}

          {tab === "Tareas" && (
            <Card titulo="Tareas con complemento (registradas por NEXE u otras apps)">
              <table style={{ width: "100%", fontSize: 14 }}>
                <thead><tr><th align="left">Concepto</th><th align="left">Referencia</th><th align="right">Importe</th><th align="left">Estado</th><th /></tr></thead>
                <tbody>
                  {datos.tareas.map((t) => (
                    <tr key={t.id}>
                      <td>{t.concepto}</td><td className="mono">{t.referencia_externa}</td><td align="right">{Number(t.importe).toLocaleString("es-ES")}</td>
                      <td><Badge tono={t.estado === "pagada" ? "ok" : t.estado === "rechazada" ? "bad" : "neutral"}>{t.estado}</Badge></td>
                      <td>
                        {t.estado === "registrada" && <button className="btn" onClick={() => accion({ accion: "tarea_validar", tarea: t.id }, "Tarea validada.")}>Validar</button>}
                        {t.estado === "validada" && <button className="btn btn-primary" onClick={() => accion({ accion: "tarea_pagar", tarea: t.id }, "Tarea pagada.")}>Pagar</button>}
                        {(t.estado === "registrada" || t.estado === "validada") && <button className="btn" onClick={() => { const m = window.prompt("Motivo (mínimo 5 caracteres)") ?? ""; if (m.length >= 5) accion({ accion: "tarea_rechazar", tarea: t.id, motivo: m }, "Tarea rechazada."); }}>Rechazar</button>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </Card>
          )}

          {tab === "Nóminas" && (
            <>
              <Card titulo="Generar y pagar la nómina de un periodo">
                <input style={{ ...campo, width: 140 }} placeholder="AAAA-MM" value={f.np ?? ""} onChange={(e) => set("np", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "nomina_periodo", periodo: f.np }, "Nómina pagada.")}>Pagar nómina</button>
                <p className="muted">Si falta presupuesto en alguna unidad, no se paga ninguno del periodo.</p>
              </Card>
              <Card titulo="Retribuciones pagadas">
                <table style={{ width: "100%", fontSize: 14 }}>
                  <thead><tr><th align="left">Fecha</th><th align="left">Concepto</th><th align="left">Unidad</th><th align="right">Importe</th></tr></thead>
                  <tbody>
                    {datos.gastos.filter((g) => g.origen === "retribucion").map((g) => (
                      <tr key={g.id}><td>{g.fecha}</td><td>{g.concepto}</td><td>{nombreUnidad(g.unidad)}</td><td align="right">{Number(g.importe).toLocaleString("es-ES")}</td></tr>
                    ))}
                  </tbody>
                </table>
              </Card>
            </>
          )}

          {tab === "Fondos y recurrentes" && (
            <>
              <Card titulo="Fondos restringidos">
                <ul>{datos.fondos.map((x) => <li key={x.id}><strong>{x.nombre}</strong> · {x.finalidad} · {Number(x.importe).toLocaleString("es-ES")} Pz · {nombreUnidad(x.unidad)}</li>)}</ul>
                <Sel valor={f.fu ?? ""} onCambio={(v) => set("fu", v)} opciones={opcionesUnidades} vacio="Unidad…" />
                <input style={campo} placeholder="Nombre" value={f.fn ?? ""} onChange={(e) => set("fn", e.target.value)} />
                <input style={{ ...campo, minWidth: 220 }} placeholder="Finalidad" value={f.ffin ?? ""} onChange={(e) => set("ffin", e.target.value)} />
                <input style={{ ...campo, width: 140 }} type="number" placeholder="Importe Pz" value={f.fi ?? ""} onChange={(e) => set("fi", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "fondo_crear", unidad: f.fu, nombre: f.fn, finalidad: f.ffin, importe: Number(f.fi) }, "Fondo creado.")}>Crear fondo</button>
              </Card>
              <Card titulo="Pagos recurrentes autorizados">
                <ul>{datos.recurrentes.map((r) => <li key={r.id}>{r.concepto} · {Number(r.importe).toLocaleString("es-ES")} Pz cada {r.periodicidad_meses} mes(es) · {nombreUnidad(r.unidad)}</li>)}</ul>
                <Sel valor={f.ru ?? ""} onCambio={(v) => set("ru", v)} opciones={opcionesUnidades} vacio="Unidad…" />
                <input style={{ ...campo, minWidth: 200 }} placeholder="Concepto" value={f.rc ?? ""} onChange={(e) => set("rc", e.target.value)} />
                <input style={{ ...campo, width: 120 }} type="number" placeholder="Importe" value={f.ri ?? ""} onChange={(e) => set("ri", e.target.value)} />
                <input style={{ ...campo, width: 90 }} type="number" min={1} max={12} placeholder="Cada N meses" value={f.rm ?? ""} onChange={(e) => set("rm", e.target.value)} />
                <input style={campo} type="date" value={f.rd ?? ""} onChange={(e) => set("rd", e.target.value)} />
                <input style={{ ...campo, minWidth: 160 }} placeholder="IBAN beneficiario" value={f.rib ?? ""} onChange={(e) => set("rib", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "recurrente_crear", unidad: f.ru, concepto: f.rc, importe: Number(f.ri), meses: Number(f.rm), desde: f.rd, iban: f.rib }, "Recurrente autorizado.")}>Autorizar</button>
                <div style={{ marginTop: 10 }}>
                  <input style={{ ...campo, width: 140 }} placeholder="AAAA-MM" value={f.rp ?? ""} onChange={(e) => set("rp", e.target.value)} />
                  <button className="btn" onClick={() => accion({ accion: "recurrentes_generar", periodo: f.rp }, "Propuestas generadas.")}>Generar propuestas del periodo</button>
                </div>
              </Card>
            </>
          )}

          {tab === "Convocatorias y solicitudes" && (
            <>
              <Card titulo="Convocatorias internas">
                <ul>{datos.convocatorias.map((c) => <li key={c.id}>{c.nombre} · {Number(c.importe).toLocaleString("es-ES")} Pz · {c.desde} → {c.hasta} · {c.estado}</li>)}</ul>
                <input style={campo} placeholder="Nombre" value={f.cn ?? ""} onChange={(e) => set("cn", e.target.value)} />
                <input style={{ ...campo, width: 140 }} type="number" placeholder="Importe Pz" value={f.ci ?? ""} onChange={(e) => set("ci", e.target.value)} />
                <input style={campo} type="date" value={f.cd ?? ""} onChange={(e) => set("cd", e.target.value)} />
                <input style={campo} type="date" value={f.ch ?? ""} onChange={(e) => set("ch", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "convocatoria_crear", nombre: f.cn, importe: Number(f.ci), desde: f.cd, hasta: f.ch }, "Convocatoria abierta.")}>Abrir convocatoria</button>
              </Card>
              <Card titulo="Solicitudes de unidades">
                <table style={{ width: "100%", fontSize: 14 }}>
                  <thead><tr><th align="left">Unidad</th><th align="left">Tipo</th><th align="right">Importe</th><th align="left">Justificación</th><th align="left">Estado</th><th /></tr></thead>
                  <tbody>
                    {datos.solicitudes.map((s) => (
                      <tr key={s.id}>
                        <td>{nombreUnidad(s.unidad)}</td><td>{s.tipo}</td><td align="right">{s.importe ? Number(s.importe).toLocaleString("es-ES") : "—"}</td>
                        <td>{s.justificacion}</td><td>{s.estado}</td>
                        <td>
                          {s.estado === "pendiente" && <>
                            <button className="btn btn-primary" onClick={() => accion({ accion: "solicitud_resolver", solicitud: s.id, decision: "concedida", resolucion: "Concedida desde el panel" }, "Solicitud concedida.")}>Conceder</button>{" "}
                            <button className="btn" onClick={() => { const m = window.prompt("Motivo de la denegación") ?? ""; if (m.length >= 5) accion({ accion: "solicitud_resolver", solicitud: s.id, decision: "denegada", resolucion: m }, "Solicitud denegada."); }}>Denegar</button>
                          </>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </Card>
              <Card titulo="Nueva solicitud de una unidad">
                {!datos.entidad?.solicitudes_activas && <p style={{ color: "#b45309" }}>Las solicitudes no están activadas en esta entidad. Actívalas en Configuración.</p>}
                <Sel valor={f.su ?? ""} onCambio={(v) => set("su", v)} opciones={opcionesUnidades} vacio="Unidad…" />
                <Sel valor={f.st ?? ""} onCambio={(v) => set("st", v)} opciones={[["ampliacion", "Ampliación de presupuesto"], ["prorroga", "Prórroga"], ["reserva_extra", "Reserva extra de un fondo"], ["financiacion", "Financiación de una convocatoria"], ["otra", "Otra"]]} vacio="Tipo…" />
                <input style={{ ...campo, width: 120 }} type="number" placeholder="Importe" value={f.si ?? ""} onChange={(e) => set("si", e.target.value)} />
                <input style={{ ...campo, minWidth: 220 }} placeholder="Referencia (fondo o convocatoria, según el tipo)" value={f.sr ?? ""} onChange={(e) => set("sr", e.target.value)} />
                <input style={campo} type="date" value={f.sf ?? ""} onChange={(e) => set("sf", e.target.value)} />
                <Sel valor={f.sc ?? ""} onCambio={(v) => set("sc", v)} opciones={datos.convocatorias.map((c): [string, string] => [c.id, c.nombre])} vacio="Convocatoria (si aplica)…" />
                <input style={{ ...campo, minWidth: 320 }} placeholder="Justificación (mínimo 20 caracteres)" value={f.sj ?? ""} onChange={(e) => set("sj", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "solicitud_crear", unidad: f.su, tipo: f.st, importe: f.si ? Number(f.si) : null, referencia: f.sr || null, nueva_fecha: f.sf || null, convocatoria: f.sc || null, justificacion: f.sj }, "Solicitud registrada.")}>Solicitar</button>
              </Card>
            </>
          )}

          {tab === "Configuración" && (
            <Card titulo="Configuración de la entidad">
              <label style={{ display: "block", marginBottom: 8 }}>
                <input type="checkbox" checked={f.cfg_sol !== undefined ? f.cfg_sol === "1" : Boolean(datos.entidad?.solicitudes_activas)}
                  onChange={(e) => set("cfg_sol", e.target.checked ? "1" : "0")} /> Activar solicitudes de unidades (prórrogas, ampliaciones, reservas extra y financiación)
              </label>
              <label style={{ display: "block", marginBottom: 8 }}>
                Doble firma para gastos por encima de (Pz, vacío = sin doble firma):{" "}
                <input style={{ ...campo, width: 140 }} type="number" value={f.cfg_df ?? (datos.entidad?.doble_firma_desde ?? "")} onChange={(e) => set("cfg_df", e.target.value)} />
              </label>
              <button className="btn btn-primary" onClick={() => accion({ accion: "config", solicitudes: (f.cfg_sol ?? (datos.entidad?.solicitudes_activas ? "1" : "0")) === "1", doble_firma: f.cfg_df ? Number(f.cfg_df) : null }, "Configuración guardada.")}>Guardar</button>
            </Card>
          )}
        </>
      )}
    </>
  );
}
