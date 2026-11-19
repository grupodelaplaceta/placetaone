"use client";
import { useState } from "react";
import { useApi, Card, Badge, Loading, Empty, ErrorBox, arr } from "../kit";
import { api } from "@/lib/api";

// Clientes de la API de bancos: orígenes de navegador autorizados. Cambiarlos afecta a qué webs pueden llamar a la API.
type Origen = { origin: string; estado: "pendiente" | "aprobado" | "rechazado"; entorno: string };
type Cliente = { id: string; name: string; scopes: string[]; rate_limit: number; active: boolean; origenes: Origen[]; integracion?: { puede_crear_sesiones: boolean; origenes_aprobados: number; origenes_pendientes: number; sesiones_24h: number } };
const ORIGEN = /^https?:\/\/[^/\s]+$/;

export default function ApiBancos() {
  const { data, error, loading, reload } = useApi<{ clientes?: Cliente[] }>("/api/admin/api-bancos", {});
  const clientes = arr<Cliente>(data.clientes);
  const [nuevo, setNuevo] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState("");

  const cambiar = async (accion: "alta" | "aprobar" | "rechazar" | "baja", cliente: string, origen: string) => {
    try {
      await api("/api/admin/api-bancos", "POST", { accion, cliente, origen });
      setMsg({ alta: `Origen ${origen} autorizado.`, aprobar: `Origen ${origen} aprobado.`, rechazar: `Origen ${origen} rechazado.`, baja: `Origen ${origen} retirado.` }[accion]);
      reload();
    } catch (e) { setMsg((e as Error).message); }
  };

  return (
    <>
      <h1>API de bancos · orígenes de navegador</h1>
      <p className="muted">Solo los orígenes de esta lista pueden llamar a la API desde una web. Las claves de servidor no se usan desde navegadores, esté o no el origen autorizado.</p>
      {msg && <p role="status" className="note">{msg}</p>}
      {error && <ErrorBox mensaje={error} onRetry={reload} />}
      {loading && !data.clientes && <Loading />}
      {!loading && !error && clientes.length === 0 && <Empty texto="No hay clientes de API. Créalos en Panel → API." />}
      {clientes.map((c) => (
        <Card key={c.id} titulo={c.name} acciones={c.active ? <Badge tono="ok">activo</Badge> : <Badge tono="neutral">inactivo</Badge>}>
          <p className="muted">Permisos: {c.scopes.join(", ") || "ninguno"} · Límite: {c.rate_limit} peticiones por minuto</p>
          {c.integracion && (
            <div className="rapidos" style={{ marginBottom: 10 }}>
              <Badge tono={c.integracion.puede_crear_sesiones ? "ok" : "bad"}>{c.integracion.puede_crear_sesiones ? "Puede crear sesiones" : "Sin permiso sesiones:crear"}</Badge>
              <Badge tono={c.integracion.origenes_aprobados > 0 ? "ok" : "warn"}>{c.integracion.origenes_aprobados} origen(es) aprobado(s)</Badge>
              {c.integracion.origenes_pendientes > 0 && <Badge tono="warn">{c.integracion.origenes_pendientes} pendiente(s) de aprobación</Badge>}
              <Badge tono={c.integracion.sesiones_24h > 0 ? "ok" : "neutral"}>{c.integracion.sesiones_24h} sesión(es) en 24 h</Badge>
            </div>
          )}
          {c.origenes.length === 0 && <p className="muted">Sin orígenes: esta entidad no puede llamar a la API desde su web.</p>}
          <ul className="lista">
            {c.origenes.map((o) => (
              <li key={o.origin}>
                <span className="mono">{o.origin}</span>
                <span>
                  <Badge tono={o.estado === "aprobado" ? "ok" : o.estado === "pendiente" ? "warn" : "bad"}>{o.estado}</Badge>{" "}
                  {o.estado === "pendiente" && <><button className="btn btn-primary" onClick={() => cambiar("aprobar", c.id, o.origin)}>Aprobar</button>{" "}<button className="btn" onClick={() => cambiar("rechazar", c.id, o.origin)}>Rechazar</button>{" "}</>}
                  <button className="btn" onClick={() => cambiar("baja", c.id, o.origin)}>Retirar</button>
                </span>
              </li>
            ))}
          </ul>
          <div style={{ display: "flex", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
            <input placeholder="https://app.tubanco.es" value={nuevo[c.id] ?? ""} onChange={(e) => setNuevo({ ...nuevo, [c.id]: e.target.value })} style={{ minWidth: 260 }} />
            <button className="btn btn-primary" disabled={!ORIGEN.test(nuevo[c.id] ?? "")} onClick={() => cambiar("alta", c.id, (nuevo[c.id] ?? "").trim())}>Autorizar origen (directo)</button>
          </div>
        </Card>
      ))}
    </>
  );
}
