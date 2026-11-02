"use client";
import { useState } from "react";
import { useApi, Card, Badge, Loading, ErrorBox } from "../kit";
import { api } from "@/lib/api";

// Cuenta institucional: entidad (CIP), organigrama, puestos, nombramientos y delegaciones.
type Entidad = { account_id: string; cip: string; nombre: string; activa: boolean };
type Unidad = { id: string; entidad: string; padre: string | null; tipo: string; nombre: string; codigo: string | null; activa: boolean };
type Puesto = { id: string; unidad: string; nombre: string; titulares_max: number; activo: boolean };
type Nombramiento = { id: string; puesto: string; persona: string; desde: string; hasta: string | null; motivo: string };
type Delegacion = { id: string; unidad: string; persona: string; permiso: string; limite: number | null; desde: string; hasta: string | null; motivo: string; revocada_at: string | null };
type Datos = { entidades: Entidad[]; unidades: Unidad[]; puestos: Puesto[]; nombramientos: Nombramiento[]; delegaciones: Delegacion[] };

const TIPOS = ["junta", "administracion", "departamento", "subdepartamento", "proyecto", "institucion", "unidad_control"];
const PERMISOS = ["consultar", "proponer", "aprobar", "ejecutar"];
const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;

export default function Organigrama() {
  const { data, error, loading, reload } = useApi<Partial<Datos>>("/api/admin/organigrama", {});
  const [msg, setMsg] = useState("");
  const [f, setF] = useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF({ ...f, [k]: v });

  const enviar = async (cuerpo: Record<string, unknown>) => {
    try { await api("/api/admin/organigrama", "POST", cuerpo); setMsg("Guardado."); reload(); }
    catch (e) { setMsg((e as Error).message); }
  };
  const nombreUnidad = (id: string) => data.unidades?.find((u) => u.id === id)?.nombre ?? id;
  const nombrePuesto = (id: string) => data.puestos?.find((p) => p.id === id)?.nombre ?? id;
  const unidadesDe = (entidad: string) => (data.unidades ?? []).filter((u) => u.entidad === entidad);

  return (
    <>
      <h1>Cuenta institucional · organigrama</h1>
      {msg && <p role="status">{msg}</p>}
      {error && <ErrorBox mensaje={error} onRetry={reload} />}
      {loading && !data.entidades && <Loading />}

      <Card titulo="1 · Entidades institucionales">
        <p className="muted">El CIP lo asigna la plataforma al crear la entidad. Una cuenta solo puede ser una entidad.</p>
        {(data.entidades ?? []).map((e) => (
          <p key={e.account_id}><strong>{e.nombre}</strong> · <span className="mono">{e.cip}</span> {e.activa ? <Badge tono="ok">activa</Badge> : <Badge tono="neutral">inactiva</Badge>}</p>
        ))}
        <input style={campo} placeholder="IBAN de la cuenta" value={f.iban ?? ""} onChange={(e) => set("iban", e.target.value)} />
        <input style={campo} placeholder="Nombre de la entidad" value={f.nombre_entidad ?? ""} onChange={(e) => set("nombre_entidad", e.target.value)} />
        <button className="btn btn-primary" onClick={() => enviar({ accion: "entidad", iban: f.iban, nombre: f.nombre_entidad })}>Crear entidad</button>
      </Card>

      <Card titulo="2 · Organigrama">
        {(data.entidades ?? []).map((e) => (
          <div key={e.account_id} style={{ marginBottom: 12 }}>
            <strong>{e.nombre}</strong>
            <ul>
              {unidadesDe(e.account_id).filter((u) => !u.padre).map((u) => <Rama key={u.id} u={u} todas={unidadesDe(e.account_id)} />)}
            </ul>
          </div>
        ))}
        <select style={campo} value={f.u_entidad ?? ""} onChange={(e) => set("u_entidad", e.target.value)}>
          <option value="">Entidad…</option>
          {(data.entidades ?? []).map((e) => <option key={e.account_id} value={e.account_id}>{e.nombre}</option>)}
        </select>
        <select style={campo} value={f.u_tipo ?? ""} onChange={(e) => set("u_tipo", e.target.value)}>
          <option value="">Tipo…</option>
          {TIPOS.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
        <select style={campo} value={f.u_padre ?? ""} onChange={(e) => set("u_padre", e.target.value)}>
          <option value="">Sin padre</option>
          {unidadesDe(f.u_entidad ?? "").map((u) => <option key={u.id} value={u.id}>{u.nombre} ({u.tipo})</option>)}
        </select>
        <input style={campo} placeholder="Nombre" value={f.u_nombre ?? ""} onChange={(e) => set("u_nombre", e.target.value)} />
        <input style={campo} placeholder="Código (opcional)" value={f.u_codigo ?? ""} onChange={(e) => set("u_codigo", e.target.value)} />
        <button className="btn btn-primary" onClick={() => enviar({ accion: "unidad", entidad: f.u_entidad, tipo: f.u_tipo, padre: f.u_padre, nombre: f.u_nombre, codigo: f.u_codigo })}>Añadir unidad</button>
      </Card>

      <Card titulo="3 · Puestos">
        <ul>{(data.puestos ?? []).map((p) => <li key={p.id}>{p.nombre} · {nombreUnidad(p.unidad)} · titulares: {p.titulares_max}</li>)}</ul>
        <select style={campo} value={f.p_unidad ?? ""} onChange={(e) => set("p_unidad", e.target.value)}>
          <option value="">Unidad…</option>
          {(data.unidades ?? []).map((u) => <option key={u.id} value={u.id}>{u.nombre} ({u.tipo})</option>)}
        </select>
        <input style={campo} placeholder="Nombre del puesto" value={f.p_nombre ?? ""} onChange={(e) => set("p_nombre", e.target.value)} />
        <input style={{ ...campo, width: 90 }} type="number" min={1} placeholder="Titulares" value={f.p_titulares ?? "1"} onChange={(e) => set("p_titulares", e.target.value)} />
        <button className="btn btn-primary" onClick={() => enviar({ accion: "puesto", unidad: f.p_unidad, nombre: f.p_nombre, titulares: Number(f.p_titulares ?? 1) })}>Crear puesto</button>
      </Card>

      <Card titulo="4 · Nombramientos y plantilla (multicargos)">
        <p className="muted">Una persona puede ocupar varios puestos. El cese cierra el periodo; no borra el historial.</p>
        <table style={{ width: "100%", fontSize: 14 }}>
          <thead><tr><th align="left">Persona (DIP interno)</th><th align="left">Puesto</th><th align="left">Desde</th><th align="left">Hasta</th><th /></tr></thead>
          <tbody>
            {(data.nombramientos ?? []).map((n) => (
              <tr key={n.id}>
                <td className="mono">{n.persona.slice(0, 8)}</td><td>{nombrePuesto(n.puesto)}</td><td>{n.desde}</td><td>{n.hasta ?? "vigente"}</td>
                <td>{!n.hasta && <button className="btn" onClick={() => enviar({ accion: "cesar", nombramiento: n.id, motivo: "Cese registrado desde el panel" })}>Cesar</button>}</td>
              </tr>
            ))}
          </tbody>
        </table>
        <select style={campo} value={f.n_puesto ?? ""} onChange={(e) => set("n_puesto", e.target.value)}>
          <option value="">Puesto…</option>
          {(data.puestos ?? []).filter((p) => p.activo).map((p) => <option key={p.id} value={p.id}>{p.nombre}</option>)}
        </select>
        <input style={campo} placeholder="DIP de la persona" value={f.n_dip ?? ""} onChange={(e) => set("n_dip", e.target.value)} />
        <input style={{ ...campo, minWidth: 260 }} placeholder="Motivo del nombramiento (mínimo 5 caracteres)" value={f.n_motivo ?? ""} onChange={(e) => set("n_motivo", e.target.value)} />
        <button className="btn btn-primary" onClick={() => enviar({ accion: "nombrar", puesto: f.n_puesto, dip: f.n_dip, motivo: f.n_motivo })}>Nombrar</button>
      </Card>

      <Card titulo="5 · Delegaciones">
        <p className="muted">Registro de quién puede actuar en un área. Todavía no condicionan las aprobaciones: eso llega en la fase de autorizaciones.</p>
        <ul>
          {(data.delegaciones ?? []).map((d) => (
            <li key={d.id}>{d.permiso} en {nombreUnidad(d.unidad)} · {d.persona.slice(0, 8)} · {d.revocada_at ? "revocada" : "vigente"} {!d.revocada_at && <button className="btn" onClick={() => enviar({ accion: "revocar_delegacion", id: d.id })}>Revocar</button>}</li>
          ))}
        </ul>
        <select style={campo} value={f.d_unidad ?? ""} onChange={(e) => set("d_unidad", e.target.value)}>
          <option value="">Unidad…</option>
          {(data.unidades ?? []).map((u) => <option key={u.id} value={u.id}>{u.nombre}</option>)}
        </select>
        <input style={campo} placeholder="DIP" value={f.d_dip ?? ""} onChange={(e) => set("d_dip", e.target.value)} />
        <select style={campo} value={f.d_permiso ?? ""} onChange={(e) => set("d_permiso", e.target.value)}>
          <option value="">Permiso…</option>
          {PERMISOS.map((p) => <option key={p} value={p}>{p}</option>)}
        </select>
        <input style={{ ...campo, width: 120 }} type="number" min={0} placeholder="Límite Pz" value={f.d_limite ?? ""} onChange={(e) => set("d_limite", e.target.value)} />
        <input style={campo} type="date" value={f.d_hasta ?? ""} onChange={(e) => set("d_hasta", e.target.value)} />
        <input style={{ ...campo, minWidth: 220 }} placeholder="Motivo (mínimo 5 caracteres)" value={f.d_motivo ?? ""} onChange={(e) => set("d_motivo", e.target.value)} />
        <button className="btn btn-primary" onClick={() => enviar({ accion: "delegar", unidad: f.d_unidad, dip: f.d_dip, permiso: f.d_permiso, limite: f.d_limite, hasta: f.d_hasta, motivo: f.d_motivo })}>Delegar</button>
      </Card>
    </>
  );
}

function Rama({ u, todas }: { u: Unidad; todas: Unidad[] }) {
  const hijos = todas.filter((x) => x.padre === u.id);
  return (
    <li>
      <span>{u.nombre}</span> <Badge tono="neutral">{u.tipo}</Badge>{u.codigo ? <span className="mono"> · {u.codigo}</span> : null}
      {hijos.length > 0 && <ul>{hijos.map((h) => <Rama key={h.id} u={h} todas={todas} />)}</ul>}
    </li>
  );
}
