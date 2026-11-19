"use client";
import { ExploradorApi } from "@/lib/api-docs-ui";

// Documentación pública de la API para los equipos de los bancos.
export default function DocumentacionApi() {
  return (
    <main style={{ maxWidth: 980, margin: "0 auto", padding: 24, fontFamily: "system-ui, sans-serif", color: "#0f172a" }}>
      <h1 style={{ marginBottom: 4 }}>Documentación de la API</h1>
      <p style={{ color: "#475569", marginTop: 0 }}>Todas las operaciones con ejemplos de petición y de respuesta en JSON. Los importes y los identificadores son ilustrativos.</p>
      <ExploradorApi />
    </main>
  );
}
