"use client";
import { useState } from "react";
import Link from "next/link";
import { useApi, Card, Stat, Badge, Loading, Empty, ErrorBox, arr, pz, fecha, type Tono } from "./kit";

// Panel de control: estado general, vencimientos próximos, auditoría y accesos rápidos.
type Alerta = { alerta: string; n: number };
type Banco = { code: string; name: string; status: string };
type Auditoria = { id: number; action: string; entity: string; entity_id: string; at: string };
type Over = { alerts?: Alerta[]; banks?: Banco[]; audit?: Auditoria[] };
type Prevision = { fecha: string; tipo: string; referencia: string; iban: string | null; importe: number | null; estado: string };
type Prev = { previsiones?: Prevision[]; kpis?: Record<string, any> };

const ETIQUETA: Record<string, string> = {
  incidencias_abiertas: "Incidencias abiertas", evaluaciones_en_revision: "Evaluaciones en revisión",
  aprobaciones_pendientes: "Aprobaciones pendientes", lotes_con_fallos: "Lotes con fallos", webhooks_fallidos: "Webhooks fallidos",
  reembolsos_pendientes_de_fondos: "Reembolsos pendientes de fondos", disputas_vencidas: "Disputas vencidas",
};
const TONO: Record<string, Tono> = { cobrable: "ok", "sin fondos": "bad", vencido: "bad", programado: "info", estimado: "neutral", cerrado: "ok", disponible: "warn" };
const hoy = () => new Date().toISOString().slice(0, 10);
const dentro = (d: number) => new Date(Date.now() + d * 864e5).toISOString().slice(0, 10);

export default function Panel() {
  const [rango] = useState(() => ({ desde: hoy(), hasta: dentro(7) }));
  const ov = useApi<Over>("/api/admin/overview", {});
  const pr = useApi<Prev>(`/api/admin/previsiones?desde=${rango.desde}&hasta=${rango.hasta}`, {});

  const alertas = arr<Alerta>(ov.data.alerts);
  const bancos = arr<Banco>(ov.data.banks);
  const auditoria = arr<Auditoria>(ov.data.audit);
  const previsiones = arr<Prevision>(pr.data.previsiones);
  const kpi = (pr.data.kpis ?? {}) as Record<string, any>;
  const totalAlertas = alertas.reduce((a, x) => a + Number(x.n ?? 0), 0);
  const recargar = () => { ov.reload(); pr.reload(); };

  return (
    <>
      <div className="pagina-h">
        <div><h1>Panel</h1><p className="muted">Estado general del sistema y vencimientos de los próximos siete días.</p></div>
        <button className="btn" onClick={recargar}>Actualizar</button>
      </div>
      {ov.error && <ErrorBox mensaje={ov.error} onRetry={ov.reload} />}
      {pr.error && <ErrorBox mensaje={`Previsiones: ${pr.error}`} onRetry={pr.reload} />}

      <div className="stats">
        <Stat label="Alertas abiertas" value={totalAlertas} tono={totalAlertas > 0 ? "bad" : "ok"} hint={`${alertas.filter((a) => a.n > 0).length} tipos con incidencias`} />
        <Stat label="Entidades activas" value={bancos.filter((b) => b.status === "active").length} hint={`${bancos.length} en total`} />
        <Stat label="Recibos vencidos" value={kpi.recibos_vencidos ?? "—"} tono={(kpi.recibos_vencidos ?? 0) > 0 ? "bad" : "ok"} hint="riesgo de recargo T57" />
        <Stat label="Pendiente de cobro" value={pz(kpi.recibos_pendientes_importe)} hint={`${kpi.recibos_pendientes ?? 0} recibos`} />
        <Stat label="Certificación" value={kpi.certificacion ?? "—"} tono={kpi.certificacion === "OK" ? "ok" : "warn"} hint={`último cierre: ${kpi.ultimo_cierre ?? "ninguno"}`} />
      </div>

      <div className="grid2">
        <Card titulo="Alertas" acciones={<Link href="/admin/estado">Ver estado →</Link>}>
          {ov.loading && !ov.data.alerts ? <Loading /> : alertas.length === 0 ? <Empty texto="No hay alertas configuradas." /> : (
            <ul className="lista">{alertas.map((a) => (
              <li key={a.alerta}><span>{ETIQUETA[a.alerta] ?? a.alerta.replaceAll("_", " ")}</span><Badge tono={a.n > 0 ? "bad" : "ok"}>{a.n}</Badge></li>
            ))}</ul>)}
        </Card>

        <Card titulo="Próximos 7 días" acciones={<Link href="/admin/previsiones">Ver todo →</Link>}>
          {pr.loading && !pr.data.previsiones ? <Loading /> : previsiones.length === 0 ? <Empty texto="No hay nada programado en los próximos siete días." /> : (
            <ul className="lista">{previsiones.slice(0, 8).map((f, i) => (
              <li key={i}>
                <span><b>{f.fecha}</b> · {f.tipo}<br /><small className="muted">{f.referencia}</small></span>
                <span>{pz(f.importe)} <Badge tono={TONO[f.estado] ?? "neutral"}>{f.estado}</Badge></span>
              </li>))}</ul>)}
        </Card>
      </div>

      <Card titulo="Auditoría reciente" acciones={<Link href="/admin/registros">Ver registros →</Link>}>
        {ov.loading && !ov.data.audit ? <Loading /> : auditoria.length === 0 ? <Empty texto="No hay actividad registrada." /> : (
          <div className="tbl-wrap"><table className="tbl">
            <thead><tr><th>Cuándo</th><th>Acción</th><th>Entidad</th><th>Identificador</th></tr></thead>
            <tbody>{auditoria.map((a) => (
              <tr key={a.id}><td>{fecha(a.at)}</td><td>{a.action}</td><td>{a.entity}</td><td className="mono">{a.entity_id}</td></tr>))}</tbody>
          </table></div>)}
      </Card>

      <Card titulo="Accesos rápidos">
        <nav className="rapidos">
          {[["/admin/previsiones", "Previsiones"], ["/admin/iva", "IVA"], ["/admin/destinos", "Destinos"], ["/admin/infraestructura", "Infraestructura"], ["/admin/fiscal", "Fiscalidad"], ["/admin/estado", "Estado"]].map(([h, l]) => (
            <Link key={h} href={h} className="rapido">{l}</Link>))}
        </nav>
      </Card>
    </>
  );
}
