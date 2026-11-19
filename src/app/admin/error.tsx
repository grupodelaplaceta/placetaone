"use client";
// Límite de error del panel: si una pantalla falla, se muestra el motivo y un botón para reintentar, sin perder la navegación.
export default function ErrorAdmin({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div role="alert" style={{ background: "#fff6f3", border: "1px solid #e8b9a8", borderRadius: 10, padding: 20, margin: 16 }}>
      <h2 style={{ marginTop: 0 }}>Esta pantalla no se ha podido mostrar</h2>
      <p style={{ color: "#6b3b2a" }}>{error.message || "Error desconocido"}</p>
      <p style={{ color: "#555", fontSize: 14 }}>Los datos no se han modificado. Puedes reintentar; si persiste, revisa la pantalla de <a href="/admin/estado">Estado</a>.</p>
      <button onClick={() => reset()}>Reintentar</button>
    </div>
  );
}
