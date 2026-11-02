"use client";
import { useEffect, useState } from "react";
import { api } from "@/lib/api";
import { dlg } from "../ui";

type Sol = { id: string; persona: string; tipo: string; importe: number; cuotas: number | null; motivo: string | null; product_id: string | null; creada: string };

export default function Solicitudes() {
  const [rows, setRows] = useState<Sol[] | null>(null); const [msg, setMsg] = useState("");
  const load = () => api("/api/admin/solicitudes").then(d => setRows(d.solicitudes)).catch(e => setMsg((e as Error).message));
  useEffect(() => { load(); }, []);
  const decidir = async (r: Sol, aprobar: boolean) => {
    const nota = await dlg.prompt(aprobar ? "Nota (opcional)" : "Motivo del rechazo");
    if (nota === null) return;
    if (!aprobar && !nota.trim()) { setMsg("Indica el motivo del rechazo."); return; }
    try { await api("/api/admin/solicitudes", "POST", { id: r.id, aprobar, nota }); setMsg(aprobar ? "Aprobada" : "Rechazada"); load(); }
    catch (e) { setMsg((e as Error).message); }
  };
  return (<>
    <h1>Solicitudes pendientes</h1>
    <p>Préstamos y cuentas que esperan revisión. Las cuentas de producto sin crédito se abren solas.</p>
    {msg && <p role="status">{msg}</p>}
    {rows === null ? <p>Cargando…</p> : rows.length === 0 ? <p>No hay solicitudes pendientes.</p> : (
      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead><tr>{["Fecha", "Tipo", "Importe", "Cuotas", "Motivo", ""].map(h => <th key={h} style={{ textAlign: "left", padding: "6px 8px", borderBottom: "1px solid #ddd" }}>{h}</th>)}</tr></thead>
        <tbody>{rows.map(r => (
          <tr key={r.id}>
            <td style={{ padding: "6px 8px" }}>{new Date(r.creada).toLocaleString("es-ES")}</td>
            <td style={{ padding: "6px 8px" }}>{r.tipo}</td>
            <td style={{ padding: "6px 8px" }}>{r.importe} Pz</td>
            <td style={{ padding: "6px 8px" }}>{r.cuotas ?? "—"}</td>
            <td style={{ padding: "6px 8px" }}>{r.motivo ?? "—"}</td>
            <td style={{ padding: "6px 8px", whiteSpace: "nowrap" }}>
              <button onClick={() => decidir(r, true)}>Aprobar</button>{" "}
              <button onClick={() => decidir(r, false)}>Rechazar</button>
            </td>
          </tr>))}
        </tbody>
      </table>)}
  </>);
}
