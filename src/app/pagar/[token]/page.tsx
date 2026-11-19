"use client";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";

// Ventana de pago. No pide ningún código: la confirma el banco de quien paga, en su propia app o banca online.
// Consulta el estado hasta que el banco decide, y avisa a la web del comercio solo a su origen registrado.
type Pago = {
  estado: string; importe: number; concepto: string; expira: string; origen: string; comercio: string;
  medio?: string; comision?: number; total?: number; aviso?: string | null; banco: { nombre: string; logo: string | null; color: string | null; texto_pie?: string | null };
};

const euros = (n: number) => n.toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " Pz";

export default function PaginaPago() {
  const { token } = useParams<{ token: string }>();
  const [pago, setPago] = useState<Pago | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let vivo = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let avisado = false;
    const pedir = async () => {
      try {
        const r = await fetch(`/api/checkout/${token}`, { cache: "no-store" });
        if (!r.ok) {
          if (vivo) setError(r.status === 404 ? "Este pago no existe o ya no está disponible." : "No se puede cargar el pago.");
          return;
        }
        const d: Pago = await r.json();
        if (!vivo) return;
        setPago(d);
        if (d.estado === "pendiente") { timer = setTimeout(pedir, 3000); return; }
        if (!avisado && window.opener) {
          avisado = true;
          window.opener.postMessage({ tipo: "placeta.checkout", estado: d.estado }, d.origen);
        }
      } catch {
        if (vivo) { setError("Sin conexión. Reintentando…"); timer = setTimeout(pedir, 5000); }
      }
    };
    pedir();
    return () => { vivo = false; if (timer) clearTimeout(timer); };
  }, [token]);

  const cancelar = async () => {
    await fetch(`/api/checkout/${token}/cancelar`, { method: "POST" }).catch(() => null);
    if (pago && window.opener) window.opener.postMessage({ tipo: "placeta.checkout", estado: "cancelado" }, pago.origen);
    setPago(pago ? { ...pago, estado: "cancelado" } : pago);
  };

  const color = pago?.banco.color ?? "#1d4ed8";
  const mensaje = !pago ? "" : pago.estado === "pendiente"
    ? `Confirma este pago en la app o la banca online de ${pago.banco.nombre}. Esperando tu confirmación…`
    : pago.estado === "pagado" ? "Pago realizado. Ya puedes cerrar esta ventana."
    : `Pago ${pago.estado}. Ya puedes cerrar esta ventana.`;

  return (
    <main style={{ fontFamily: "system-ui, sans-serif", maxWidth: 400, margin: "24px auto", padding: 20, background: "#fff", borderRadius: 12, boxShadow: "0 2px 16px rgba(0,0,0,.08)" }}>
      {!pago && !error && <p role="status">Cargando…</p>}
      {error && !pago && <p role="alert">{error}</p>}
      {pago && (
        <>
          <header style={{ display: "flex", alignItems: "center", gap: 12, borderBottom: `3px solid ${color}`, paddingBottom: 12 }}>
            {pago.banco.logo
              ? <img src={pago.banco.logo} alt={pago.banco.nombre} style={{ height: 36, maxWidth: 160, objectFit: "contain" }} />
              : <strong>{pago.banco.nombre}</strong>}
          </header>
          <p style={{ color: "#555", margin: "12px 0 4px" }}>Pago a <strong>{pago.comercio}</strong></p>
          <p style={{ fontSize: 28, fontWeight: 700, margin: "0 0 4px" }}>{euros(pago.importe)}</p>
          {(pago.comision ?? 0) > 0 && <p style={{ color: "#555", margin: "0 0 4px", fontSize: 14 }}>Comisión interbancaria {euros(pago.comision ?? 0)} · total {euros(pago.total ?? pago.importe)}</p>}
          {pago.aviso && <p style={{ color: "#777", margin: "0 0 4px", fontSize: 12 }}>{pago.aviso}</p>}
          {pago.banco.texto_pie && <p style={{ color: "#777", margin: "12px 0 0", fontSize: 11 }}>{pago.banco.texto_pie}</p>}
          <p style={{ margin: 0 }}>{pago.concepto}</p>
          <p role="status" style={{ marginTop: 20 }}>{mensaje}</p>
          {pago.estado === "pendiente" && (
            <button onClick={cancelar} style={{ marginTop: 8, padding: 12, background: "#eee", border: 0, borderRadius: 8 }}>Cancelar pago</button>
          )}
          {error && <p role="alert" style={{ color: "#b91c1c" }}>{error}</p>}
        </>
      )}
    </main>
  );
}
