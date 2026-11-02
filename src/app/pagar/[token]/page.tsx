"use client";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";

// Ventana de pago de la pasarela. Muestra el logo y los colores del banco y pide el código de verificación.
// Avisa a la web que la abrió (window.opener) solo al origen registrado y aprobado por el banco.
type Pago = {
  estado: string; importe: number; concepto: string; expira: string; intentos_restantes: number;
  origen: string; comercio: string; banco: { nombre: string; logo: string | null; color: string | null };
};

const euros = (n: number) => n.toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " Pz";

export default function PaginaPago() {
  const { token } = useParams<{ token: string }>();
  const [pago, setPago] = useState<Pago | null>(null);
  const [error, setError] = useState("");
  const [codigo, setCodigo] = useState("");
  const [enviando, setEnviando] = useState(false);
  const [final, setFinal] = useState<string | null>(null);

  useEffect(() => {
    fetch(`/api/checkout/${token}`, { cache: "no-store" })
      .then(async (r) => {
        if (!r.ok) { setError(r.status === 404 ? "Este pago no existe o ya no está disponible." : "No se puede cargar el pago."); return; }
        const d: Pago = await r.json();
        setPago(d);
        if (d.estado !== "pendiente") setFinal(d.estado);
      })
      .catch(() => setError("Sin conexión. Vuelve a intentarlo."));
  }, [token]);

  const avisar = (datos: Record<string, unknown>) => {
    if (pago && window.opener) window.opener.postMessage({ tipo: "placeta.checkout", ...datos }, pago.origen);
  };

  const confirmar = async () => {
    if (!/^\d{6}$/.test(codigo)) return;
    setEnviando(true); setError("");
    try {
      const r = await fetch(`/api/checkout/${token}/confirmar`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ codigo }),
      });
      const d = await r.json().catch(() => ({}));
      if (d.ok) { setFinal("pagado"); avisar({ estado: "pagado", transaccion: d.transaccion }); return; }
      setCodigo("");
      if (d.estado && d.estado !== "pendiente") { setFinal(d.estado); avisar({ estado: d.estado, error: d.error }); }
      setError(typeof d.intentos_restantes === "number" ? `${d.error}. Te quedan ${d.intentos_restantes} intentos.` : (d.error ?? "No se ha podido confirmar el pago."));
    } catch {
      setError("Sin conexión. Vuelve a intentarlo.");
    } finally {
      setEnviando(false);
    }
  };

  const cancelar = async () => {
    await fetch(`/api/checkout/${token}/cancelar`, { method: "POST" }).catch(() => null);
    setFinal("cancelado");
    avisar({ estado: "cancelado" });
  };

  const color = pago?.banco.color ?? "#1d4ed8";
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
          <p style={{ margin: 0 }}>{pago.concepto}</p>
          {final ? (
            <p role="status" style={{ marginTop: 20 }}>
              {final === "pagado" ? "Pago realizado. Ya puedes cerrar esta ventana." : `Pago ${final}. Ya puedes cerrar esta ventana.`}
            </p>
          ) : (
            <>
              <label htmlFor="codigo" style={{ display: "block", marginTop: 20 }}>Código de verificación de tu banco</label>
              <input id="codigo" inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={codigo}
                onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ""))}
                style={{ width: "100%", fontSize: 22, letterSpacing: 6, padding: 10, boxSizing: "border-box" }} />
              <p style={{ color: "#666", fontSize: 13 }}>
                Te lo envía tu banco. No lo compartas con el comercio. Te quedan {pago.intentos_restantes} intentos.
              </p>
              {error && <p role="alert" style={{ color: "#b91c1c" }}>{error}</p>}
              <div style={{ display: "flex", gap: 8, marginTop: 12 }}>
                <button onClick={confirmar} disabled={enviando || codigo.length !== 6}
                  style={{ flex: 1, padding: 12, background: color, color: "#fff", border: 0, borderRadius: 8, fontWeight: 600 }}>
                  {enviando ? "Confirmando…" : "Confirmar pago"}
                </button>
                <button onClick={cancelar} style={{ padding: 12, background: "#eee", border: 0, borderRadius: 8 }}>Cancelar</button>
              </div>
            </>
          )}
        </>
      )}
    </main>
  );
}
