"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Empresas de una entidad: alta, titulares, pasarela (alta, rotación de clave y contrato), y estado.
type Banco = { id: string; code: string; name: string; nombre_visible?: string | null };
type Emp = { id: string; nombre: string; identificador_fiscal: string; estado: string; creada: string; entidad_cip?: string | null };
type Det = { titulares: { dip: string; rol: string; desde: string; hasta: string | null }[]; cuentas: { iban: string; nombre: string }[];
  pasarela: { client_id: string; activa: boolean } | null; contrato_version: number | null };
type Nodo = { id: string; padre: string | null; tipo: string; nombre: string; codigo: string | null; activa: boolean };
type Ficha = { empresa: { nombre: string; identificador_fiscal: string; estado: string }; entidad: { cip: string; nombre: string; activa: boolean } | null; ejercicio: number;
  organigrama?: Nodo[]; departamentos?: { id: string; nombre: string; tipo: string; presupuesto_anual: number; pagado: number; comprometido: number }[];
  nominas?: { periodo: string; pagos: number; total: number }[] };
function Arbol({ nodos, padre }: { nodos: Nodo[]; padre: string | null }) {
  const hijos = nodos.filter((n) => (n.padre ?? null) === padre);
  if (!hijos.length) return null;
  return <ul>{hijos.map((n) => <li key={n.id}>{n.nombre} <span className="muted">({n.tipo}{n.codigo ? `, ${n.codigo}` : ""})</span>{!n.activa && <Badge tono="neutral"> inactiva</Badge>}<Arbol nodos={nodos} padre={n.id} /></li>)}</ul>;
}
const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;

export default function EmpresasAdmin() {
  const [bancos, setBancos] = useState<Banco[]>([]);
  const [bank, setBank] = useState("");
  const [empresas, setEmpresas] = useState<Emp[]>([]);
  const [sel, setSel] = useState("");
  const [det, setDet] = useState<Det | null>(null);
  const [msg, setMsg] = useState("");
  const [clave, setClave] = useState("");
  const [contrato, setContrato] = useState("");
  const [ficha, setFicha] = useState<Ficha | null>(null);
  const [f, setF] = useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));

  useEffect(() => { api("/api/admin/pasarela").then((r: { bancos?: Banco[] }) => setBancos(r.bancos ?? [])).catch((e) => setMsg((e as Error).message)); }, []);
  const cargarEmpresas = (b: string) => { if (b) api(`/api/admin/empresas?bank_id=${encodeURIComponent(b)}`).then((r: { empresas?: Emp[] }) => setEmpresas(r.empresas ?? [])).catch((e) => setMsg((e as Error).message)); };
  const cargarDetalle = (b: string, e: string) => { if (b && e) api(`/api/admin/empresas?bank_id=${encodeURIComponent(b)}&empresa=${encodeURIComponent(e)}`).then((r: { empresa?: Det }) => setDet(r.empresa ?? null)).catch((x) => setMsg((x as Error).message)); };
  const cargarFicha = (b: string, e: string) => {
    if (b && e) api(`/api/admin/empresas?bank_id=${encodeURIComponent(b)}&empresa=${encodeURIComponent(e)}&ficha=1`).then((r: { ficha?: Ficha }) => setFicha(r.ficha ?? null)).catch((x) => setMsg((x as Error).message));
  };
  useEffect(() => { setEmpresas([]); setSel(""); setDet(null); cargarEmpresas(bank); }, [bank]);
  useEffect(() => { setDet(null); setFicha(null); cargarDetalle(bank, sel); cargarFicha(bank, sel); }, [sel]);

  const accion = async (cuerpo: Record<string, unknown>, ok: string) => {
    try {
      const r = await api("/api/admin/empresas", "POST", { bank_id: bank, empresa: sel, ...cuerpo });
      setMsg(ok);
      if (r.clave) setClave(r.clave);
      if (r.contrato?.texto) setContrato(r.contrato.texto);
      cargarEmpresas(bank); cargarDetalle(bank, sel); cargarFicha(bank, sel);
    } catch (e) { setMsg((e as Error).message); }
  };

  return (
    <>
      <h1>Empresas</h1>
      <div style={{ marginBottom: 10 }}>
        <select style={{ ...campo, minWidth: 320 }} value={bank} onChange={(e) => setBank(e.target.value)}>
          <option value="">Elige una entidad…</option>
          {bancos.map((b) => <option key={b.id} value={b.id}>{b.nombre_visible ?? b.name} ({b.code})</option>)}
        </select>
      </div>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      {!bank && <p className="muted">Elige una entidad.</p>}

      {bank && (
        <>
          <Card titulo="Empresas">
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">Nombre</th><th align="left">CIP (identificador)</th><th align="left">Entidad institucional</th><th align="left">Estado</th><th /></tr></thead>
              <tbody>{empresas.map((e) => (
                <tr key={e.id}><td>{e.nombre}</td><td className="mono">{e.identificador_fiscal}</td><td>{e.entidad_cip ? <Badge tono="ok">{e.entidad_cip}</Badge> : <Badge tono="bad">sin vincular</Badge>}</td>
                  <td><Badge tono={e.estado === "activa" ? "ok" : "bad"}>{e.estado}</Badge></td>
                  <td><button className="btn" onClick={() => setSel(e.id)}>Abrir</button></td></tr>))}</tbody>
            </table>
            <div style={{ marginTop: 10 }}>
              <input style={campo} placeholder="Nombre" value={f.nombre ?? ""} onChange={(e) => set("nombre", e.target.value)} />
              <input style={campo} placeholder="CIP de la entidad (CIP-00000001)" value={f.fiscal ?? ""} onChange={(e) => set("fiscal", e.target.value)} />
              <input style={campo} placeholder="DIP del titular inicial" value={f.tdip ?? ""} onChange={(e) => set("tdip", e.target.value)} />
              <input style={{ ...campo, minWidth: 260 }} placeholder="Cuentas de empresa (IBAN separados por comas)" value={f.cuentas ?? ""} onChange={(e) => set("cuentas", e.target.value)} />
              <button className="btn btn-primary" onClick={() => accion({ accion: "alta", nombre: f.nombre ?? "", identificador_fiscal: f.fiscal ?? "", titular_dip: f.tdip ?? "",
                cuentas: (f.cuentas ?? "").split(",").map((x) => x.trim()).filter(Boolean) }, "Empresa creada.")}>Dar de alta</button>
            </div>
          </Card>

          {sel && det && (
            <>
              <Card titulo="Titulares y cuentas">
                <table style={{ width: "100%", fontSize: 14 }}>
                  <thead><tr><th align="left">DIP</th><th align="left">Rol</th><th align="left">Desde</th><th align="left">Hasta</th></tr></thead>
                  <tbody>{det.titulares.map((t, i) => <tr key={i}><td className="mono">{t.dip}</td><td>{t.rol}</td><td>{t.desde}</td><td>{t.hasta ?? "activo"}</td></tr>)}</tbody>
                </table>
                <p>Cuentas: {det.cuentas.map((c) => c.iban).join(", ") || "ninguna"}</p>
                <input style={campo} placeholder="DIP de un titular que autoriza" value={f.actor ?? ""} onChange={(e) => set("actor", e.target.value)} />
                <input style={campo} placeholder="DIP del nuevo titular / autorizado" value={f.dip ?? ""} onChange={(e) => set("dip", e.target.value)} />
                <select style={campo} value={f.rol ?? "autorizado"} onChange={(e) => set("rol", e.target.value)}><option value="titular">Titular</option><option value="autorizado">Autorizado</option><option value="lector">Lector</option></select>
                <input style={campo} placeholder="Motivo" value={f.motivo ?? ""} onChange={(e) => set("motivo", e.target.value)} />
                <button className="btn" onClick={() => accion({ accion: "titular_alta", dip: f.dip ?? "", dip_actor: f.actor ?? "", rol: f.rol ?? "autorizado", motivo: f.motivo ?? "" }, "Titular dado de alta.")}>Dar de alta titular</button>{" "}
                <button className="btn" onClick={() => accion({ accion: "titular_cese", dip: f.dip ?? "", dip_actor: f.actor ?? "", motivo: f.motivo ?? "" }, "Titular dado de baja.")}>Dar de baja titular</button>
              </Card>

              <Card titulo="Pasarela de la empresa">
                <p>Estado: {det.pasarela?.activa ? <Badge tono="ok">activa</Badge> : <Badge tono="neutral">sin pasarela</Badge>} · Contrato: versión {det.contrato_version ?? "—"}</p>
                {clave && (
                  <div style={{ background: "#fef3c7", padding: 10, borderRadius: 6, marginBottom: 10 }}>
                    <strong>Clave nueva:</strong> <code style={{ wordBreak: "break-all" }}>{clave}</code>
                    <p className="muted">Entrégala ahora al titular: no se vuelve a mostrar.</p>
                    <button className="btn" onClick={() => setClave("")}>Ya la he entregado</button>
                  </div>
                )}
                {contrato && <pre style={{ whiteSpace: "pre-wrap", fontSize: 12, background: "#f8fafc", padding: 10, borderRadius: 6 }}>{contrato}</pre>}
                <input style={campo} placeholder="DIP de un titular (actor)" value={f.actor ?? ""} onChange={(e) => set("actor", e.target.value)} />
                <button className="btn btn-primary" onClick={() => accion({ accion: "pasarela_alta", dip_actor: f.actor ?? "", nombre_cliente: `Pasarela ${sel.slice(0, 8)}` }, "Pasarela creada.")}>Dar de alta pasarela</button>{" "}
                <button className="btn" onClick={() => accion({ accion: "pasarela_rotar", dip_actor: f.actor ?? "" }, "Clave rotada.")}>Rotar clave</button>
              </Card>

              <Card titulo="Entidad institucional (CIP), organigrama, presupuesto y nóminas">
                {!ficha?.entidad ? (
                  <>
                    <p className="muted">Esta empresa no tiene entidad institucional vinculada. Vincúlala para ver su organigrama, presupuesto por departamento y nóminas.</p>
                    <input style={campo} placeholder="CIP de la entidad (CIP-00000001)" value={f.cip ?? ""} onChange={(e) => set("cip", e.target.value)} />
                    <input style={campo} placeholder="DIP de un titular (actor)" value={f.actor ?? ""} onChange={(e) => set("actor", e.target.value)} />
                    <button className="btn btn-primary" onClick={() => accion({ accion: "vincular_entidad", cip: f.cip ?? "", dip_actor: f.actor ?? "" }, "Entidad vinculada.")}>Vincular entidad</button>
                  </>
                ) : (
                  <>
                    <p>Entidad: <strong>{ficha.entidad.nombre}</strong> ({ficha.entidad.cip}) · Ejercicio {ficha.ejercicio}</p>
                    <h3>Organigrama</h3>
                    {(ficha.organigrama ?? []).length === 0 ? <p className="muted">Sin unidades creadas.</p> : <Arbol nodos={ficha.organigrama ?? []} padre={null} />}
                    <h3>Presupuesto por departamento</h3>
                    <table style={{ width: "100%", fontSize: 14 }}>
                      <thead><tr><th align="left">Unidad</th><th align="left">Tipo</th><th align="right">Asignado</th><th align="right">Pagado</th><th align="right">Comprometido</th><th align="right">Disponible</th></tr></thead>
                      <tbody>{(ficha.departamentos ?? []).map((d) => (
                        <tr key={d.id}><td>{d.nombre}</td><td>{d.tipo}</td><td align="right">{d.presupuesto_anual.toFixed(2)} Pz</td><td align="right">{d.pagado.toFixed(2)} Pz</td>
                          <td align="right">{d.comprometido.toFixed(2)} Pz</td><td align="right"><Badge tono={d.presupuesto_anual - d.pagado - d.comprometido >= 0 ? "ok" : "bad"}>{(d.presupuesto_anual - d.pagado - d.comprometido).toFixed(2)} Pz</Badge></td></tr>))}</tbody>
                    </table>
                    <h3>Nóminas pagadas</h3>
                    <table style={{ width: "100%", fontSize: 14 }}>
                      <thead><tr><th align="left">Mes</th><th align="right">Pagos</th><th align="right">Total</th></tr></thead>
                      <tbody>{(ficha.nominas ?? []).map((n) => <tr key={n.periodo}><td>{n.periodo}</td><td align="right">{n.pagos}</td><td align="right">{Number(n.total).toFixed(2)} Pz</td></tr>)}</tbody>
                    </table>
                  </>
                )}
              </Card>
              <Card titulo="Estado de la empresa">
                <select style={campo} value={f.estado ?? "activa"} onChange={(e) => set("estado", e.target.value)}><option value="activa">Activa</option><option value="suspendida">Suspendida</option><option value="baja">Baja</option></select>
                <input style={campo} placeholder="Motivo" value={f.motivo2 ?? ""} onChange={(e) => set("motivo2", e.target.value)} />
                <button className="btn" onClick={() => accion({ accion: "estado", estado: f.estado ?? "activa", motivo: f.motivo2 ?? "", dip_actor: f.actor ?? "" }, "Estado actualizado.")}>Cambiar estado</button>
                <p className="muted">Suspender o dar de baja desactiva la pasarela de la empresa.</p>
              </Card>
            </>
          )}
        </>
      )}
    </>
  );
}
