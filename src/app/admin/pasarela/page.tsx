"use client";
import { useEffect, useState } from "react";
import { Card, Badge } from "../kit";
import { api } from "@/lib/api";

// Configuración de la pasarela, branding y webhooks de cada entidad, y seguimiento de entregas con reintento manual.
type Banco = { id: string; code: string; name: string; nombre_visible?: string | null };
type Config = { activa: boolean; minutos_defecto: number; importe_maximo: number; destinos: string[] } | null;
type Brand = { nombre_visible?: string | null; logo_url?: string | null; color_principal?: string | null; texto_pie?: string | null } | null;
type Hook = { id: string; url: string; events: string[]; active: boolean };
type Entrega = { id: number; evento: string; estado: string; intentos: number; creada: string; referencia?: string | null };
type Datos = { bancos?: Banco[]; config?: Config; branding?: Brand; webhooks?: Hook[]; entregas?: Entrega[] };

const campo = { padding: 6, borderRadius: 6, border: "1px solid #cbd5e1", marginRight: 6, marginBottom: 6 } as const;

export default function PasarelaAdmin() {
  const [bancos, setBancos] = useState<Banco[]>([]);
  const [bank, setBank] = useState("");
  const [datos, setDatos] = useState<Datos>({});
  const [msg, setMsg] = useState("");
  const [secreto, setSecreto] = useState("");
  const [f, setF] = useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF((x) => ({ ...x, [k]: v }));
  const val = (k: string, base: string) => (f[k] !== undefined ? f[k] : base);

  useEffect(() => {
    api("/api/admin/pasarela").then((r: Datos) => setBancos(r.bancos ?? [])).catch((e) => setMsg((e as Error).message));
  }, []);

  const cargar = (b: string) => {
    if (!b) return;
    api(`/api/admin/pasarela?bank_id=${encodeURIComponent(b)}`).then((r: Datos) => setDatos(r)).catch((e) => setMsg((e as Error).message));
  };

  useEffect(() => { setDatos({}); setSecreto(""); cargar(bank); }, [bank]);

  const accion = async (cuerpo: Record<string, unknown>, ok: string) => {
    try {
      const r = await api("/api/admin/pasarela", "POST", { bank_id: bank, ...cuerpo });
      setMsg(ok);
      if (r.secreto) setSecreto(r.secreto);
      cargar(bank);
    } catch (e) { setMsg((e as Error).message); }
  };

  const cfg = datos.config;
  const br = datos.branding;
  const destinosBase = cfg?.destinos ?? ["business", "system"];

  return (
    <>
      <h1>Pasarela, branding y webhooks</h1>
      <div style={{ marginBottom: 10 }}>
        <select style={{ ...campo, minWidth: 320 }} value={bank} onChange={(e) => setBank(e.target.value)}>
          <option value="">Elige una entidad…</option>
          {bancos.map((b) => <option key={b.id} value={b.id}>{b.nombre_visible ?? b.name} ({b.code})</option>)}
        </select>
      </div>
      {msg && <p role="status" style={{ background: "#f1f5f9", padding: 8, borderRadius: 6 }}>{msg}</p>}
      {!bank && <p className="muted">Elige una entidad para configurarla.</p>}

      {bank && (
        <>
          <Card titulo="Producto pasarela">
            <p>Estado: {cfg?.activa ? <Badge tono="ok">activa</Badge> : <Badge tono="neutral">inactiva</Badge>}</p>
            <label style={{ display: "block", marginBottom: 6 }}>
              <input type="checkbox" checked={val("pa", cfg?.activa ? "1" : "0") === "1"} onChange={(e) => set("pa", e.target.checked ? "1" : "0")} /> Pasarela activa
            </label>
            <div>
              <input style={{ ...campo, width: 120 }} type="number" min={3} max={30} placeholder="Validez (min)" value={val("pm", String(cfg?.minutos_defecto ?? 15))} onChange={(e) => set("pm", e.target.value)} />
              <input style={{ ...campo, width: 160 }} type="number" placeholder="Importe máximo" value={val("pi", String(cfg?.importe_maximo ?? 50000))} onChange={(e) => set("pi", e.target.value)} />
            </div>
            <label style={{ display: "block", marginBottom: 6 }}>
              <input type="checkbox" checked={val("db", destinosBase.includes("business") ? "1" : "0") === "1"} onChange={(e) => set("db", e.target.checked ? "1" : "0")} /> Cobra a cuentas de empresa
            </label>
            <label style={{ display: "block", marginBottom: 6 }}>
              <input type="checkbox" checked={val("ds", destinosBase.includes("system") ? "1" : "0") === "1"} onChange={(e) => set("ds", e.target.checked ? "1" : "0")} /> Cobra a cuentas institucionales
            </label>
            <button className="btn btn-primary" onClick={() => {
              const destinos: string[] = [];
              if (val("db", destinosBase.includes("business") ? "1" : "0") === "1") destinos.push("business");
              if (val("ds", destinosBase.includes("system") ? "1" : "0") === "1") destinos.push("system");
              accion({ accion: "pasarela", activa: val("pa", cfg?.activa ? "1" : "0") === "1", minutos_defecto: Number(val("pm", String(cfg?.minutos_defecto ?? 15))),
                importe_maximo: Number(val("pi", String(cfg?.importe_maximo ?? 50000))), destinos }, "Pasarela guardada.");
            }}>Guardar pasarela</button>
          </Card>

          <Card titulo="Branding en la ventana de pago">
            <input style={{ ...campo, minWidth: 220 }} placeholder={br?.nombre_visible ?? "Nombre visible"} value={val("bn", br?.nombre_visible ?? "")} onChange={(e) => set("bn", e.target.value)} />
            <input style={{ ...campo, minWidth: 260 }} placeholder="Logo (URL https)" value={val("bl", br?.logo_url ?? "")} onChange={(e) => set("bl", e.target.value)} />
            <input style={{ ...campo, width: 120 }} placeholder="#RRGGBB" value={val("bc", br?.color_principal ?? "")} onChange={(e) => set("bc", e.target.value)} />
            <input style={{ ...campo, minWidth: 320 }} placeholder="Texto legal (máximo 200)" value={val("bt", br?.texto_pie ?? "")} onChange={(e) => set("bt", e.target.value)} />
            <div><button className="btn btn-primary" onClick={() => accion({ accion: "branding", nombre_visible: val("bn", br?.nombre_visible ?? ""), logo_url: val("bl", br?.logo_url ?? ""),
              color_principal: val("bc", br?.color_principal ?? ""), texto_pie: val("bt", br?.texto_pie ?? "") }, "Branding guardado.")}>Guardar branding</button></div>
          </Card>

          <Card titulo="Webhooks">
            {secreto && (
              <div style={{ background: "#fef3c7", padding: 10, borderRadius: 6, marginBottom: 10 }}>
                <strong>Secreto nuevo:</strong> <code style={{ wordBreak: "break-all" }}>{secreto}</code>
                <p className="muted">Guárdalo ahora: no se vuelve a mostrar.</p>
                <button className="btn" onClick={() => setSecreto("")}>Ya lo he guardado</button>
              </div>
            )}
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">URL</th><th align="left">Eventos</th><th align="left">Activo</th><th /></tr></thead>
              <tbody>
                {(datos.webhooks ?? []).map((h) => (
                  <tr key={h.id}>
                    <td className="mono">{h.url}</td><td>{h.events.join(", ")}</td><td>{h.active ? "sí" : "no"}</td>
                    <td>
                      <button className="btn" onClick={() => accion({ accion: "webhook_rotar", id: h.id }, "Secreto rotado.")}>Rotar secreto</button>{" "}
                      <button className="btn" onClick={() => accion({ accion: "webhook_baja", id: h.id }, "Webhook dado de baja.")}>Dar de baja</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <div style={{ marginTop: 10 }}>
              <input style={{ ...campo, minWidth: 300 }} placeholder="https://… (URL de destino)" value={f.wu ?? ""} onChange={(e) => set("wu", e.target.value)} />
              <input style={{ ...campo, minWidth: 260 }} placeholder="Eventos separados por comas (* = todos)" value={f.we ?? "*"} onChange={(e) => set("we", e.target.value)} />
              <button className="btn btn-primary" onClick={() => accion({ accion: "webhook_crear", url: f.wu ?? "", eventos: (f.we ?? "*").split(",").map((x) => x.trim()).filter(Boolean) }, "Webhook creado.")}>Crear webhook</button>
            </div>
          </Card>

          <Card titulo="Entregas de eventos">
            <table style={{ width: "100%", fontSize: 14 }}>
              <thead><tr><th align="left">#</th><th align="left">Evento</th><th align="left">Referencia</th><th align="left">Estado</th><th align="right">Intentos</th><th align="left">Fecha</th><th /></tr></thead>
              <tbody>
                {(datos.entregas ?? []).map((e) => (
                  <tr key={e.id}>
                    <td>{e.id}</td><td>{e.evento}</td><td className="mono">{e.referencia ?? "—"}</td>
                    <td><Badge tono={e.estado === "sent" ? "ok" : e.estado === "failed" ? "bad" : "neutral"}>{e.estado}</Badge></td>
                    <td align="right">{e.intentos}</td><td>{new Date(e.creada).toLocaleString("es-ES")}</td>
                    <td>{e.estado === "failed" && <button className="btn" onClick={() => accion({ accion: "entrega_reintentar", id: e.id }, "Reintento programado.")}>Reintentar</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Card>
        </>
      )}
    </>
  );
}
