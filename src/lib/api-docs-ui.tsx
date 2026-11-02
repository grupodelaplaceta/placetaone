"use client";
import { useEffect, useMemo, useState } from "react";

// Explorador de la API: pestañas, búsqueda y ejemplos JSON. Lo usan /docs/api (público) y el panel (/admin/api).
type Respuesta = { description?: string; content?: { "application/json"?: { example?: unknown } } };
type Operacion = {
  method: string; path: string; summary?: string; description?: string;
  "x-permiso"?: string; "x-grupo"?: string; security?: unknown[];
  parameters?: { name: string; in: string; required?: boolean; description?: string }[];
  requestBody?: { content?: { "application/json"?: { example?: unknown } } };
  responses?: Record<string, Respuesta>;
};
type Especificacion = {
  paths: Record<string, Record<string, Omit<Operacion, "method" | "path">>>;
  "x-webhooks"?: Record<string, { description?: string; example?: unknown }>;
};

const PESTANAS = ["Todas", "Banco (servidor)", "Usuario", "Pasarela de pago", "Diseños y tarjetas", "Nóminas y planes", "Cuenta institucional", "Webhooks", "Errores y límites"];
const COLOR: Record<string, string> = { GET: "#0f766e", POST: "#1d4ed8", PUT: "#7c3aed", PATCH: "#b45309", DELETE: "#b91c1c" };

function aplanar(spec: Especificacion): Operacion[] {
  const out: Operacion[] = [];
  for (const [path, metodos] of Object.entries(spec.paths)) {
    for (const [method, op] of Object.entries(metodos)) out.push({ method: method.toUpperCase(), path, ...op });
  }
  return out.sort((a, b) => a.path.localeCompare(b.path) || a.method.localeCompare(b.method));
}

function Copiar({ texto }: { texto: string }) {
  const [ok, setOk] = useState(false);
  return (
    <button type="button"
      onClick={async () => {
        try { await navigator.clipboard.writeText(texto); setOk(true); setTimeout(() => setOk(false), 1500); } catch { /* el navegador no permite copiar */ }
      }}
      style={{ fontSize: 12, padding: "2px 8px", borderRadius: 6, border: "1px solid #cbd5e1", background: "#fff", cursor: "pointer" }}>
      {ok ? "Copiado" : "Copiar"}
    </button>
  );
}

function Bloque({ titulo, valor }: { titulo: string; valor: unknown }) {
  const texto = JSON.stringify(valor, null, 2);
  return (
    <div style={{ marginTop: 10 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <strong style={{ fontSize: 13 }}>{titulo}</strong>
        <Copiar texto={texto} />
      </div>
      <pre style={{ background: "#0f172a", color: "#e2e8f0", padding: 12, borderRadius: 8, overflowX: "auto", fontSize: 12.5, margin: "6px 0 0" }}>{texto}</pre>
    </div>
  );
}

function Tarjeta({ op }: { op: Operacion }) {
  const respuestas = Object.entries(op.responses ?? {});
  const exitosa = respuestas.find(([c]) => c.startsWith("2"));
  const errores = respuestas.filter(([c]) => !c.startsWith("2"));
  const peticion = op.requestBody?.content?.["application/json"]?.example;
  const respuesta = exitosa?.[1].content?.["application/json"]?.example;
  return (
    <details style={{ border: "1px solid #e2e8f0", borderRadius: 10, padding: "10px 14px", marginBottom: 10, background: "#fff" }}>
      <summary style={{ cursor: "pointer", display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
        <span style={{ background: COLOR[op.method] ?? "#475569", color: "#fff", borderRadius: 6, padding: "2px 8px", fontSize: 12, fontWeight: 700 }}>{op.method}</span>
        <code style={{ fontSize: 14 }}>{op.path}</code>
        <span style={{ color: "#475569" }}>{op.summary}</span>
        {op["x-permiso"] && <span style={{ fontSize: 12, background: "#f1f5f9", borderRadius: 6, padding: "2px 6px" }}>permiso: {op["x-permiso"]}</span>}
        {op.security && op.security.length === 0 && <span style={{ fontSize: 12, background: "#ecfdf5", borderRadius: 6, padding: "2px 6px" }}>pública</span>}
      </summary>
      {op.description && <p style={{ color: "#334155" }}>{op.description}</p>}
      {op.parameters && op.parameters.length > 0 && (
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13, marginTop: 8 }}>
          <thead><tr><th align="left">Parámetro</th><th align="left">Dónde</th><th align="left">Obligatorio</th><th align="left">Descripción</th></tr></thead>
          <tbody>
            {op.parameters.map((p) => (
              <tr key={p.in + p.name}><td><code>{p.name}</code></td><td>{p.in}</td><td>{p.required ? "sí" : "no"}</td><td>{p.description}</td></tr>
            ))}
          </tbody>
        </table>
      )}
      {peticion !== undefined && <Bloque titulo="Petición (JSON)" valor={peticion} />}
      {exitosa && <Bloque titulo={`Respuesta ${exitosa[0]} (JSON)`} valor={respuesta} />}
      {errores.length > 0 && (
        <p style={{ fontSize: 13, color: "#475569", marginTop: 10 }}>
          Errores: {errores.map(([c, r]) => `${c} ${r.description ?? ""}`).join(" · ")}
        </p>
      )}
    </details>
  );
}

function Webhooks({ spec }: { spec: Especificacion }) {
  const hooks = Object.entries(spec["x-webhooks"] ?? {});
  return (
    <>
      <p style={{ color: "#334155" }}>
        Placeta envía cada evento a la URL de tu webhook con <code>POST</code>. El cuerpo tiene la forma de abajo. La firma va en la cabecera
        <code> x-placeta-signature</code>: HMAC-SHA256 en hexadecimal del cuerpo exacto, con el secreto de tu webhook. Verifica la firma antes de actuar.
      </p>
      {hooks.map(([nombre, h]) => (
        <div key={nombre} style={{ border: "1px solid #e2e8f0", borderRadius: 10, padding: 14, marginBottom: 12, background: "#fff" }}>
          <h3 style={{ margin: "0 0 4px" }}><code>{nombre}</code></h3>
          <p style={{ margin: "0 0 8px", color: "#334155" }}>{h.description}</p>
          <Bloque titulo="Cuerpo del evento (JSON)" valor={h.example} />
        </div>
      ))}
    </>
  );
}

const CODIGOS: [string, string][] = [
  ["400", "Datos no válidos o incompletos. No reintentar sin corregir la petición."],
  ["401", "Token, clave o firma no válidos o caducados. Renueva la sesión."],
  ["403", "Permiso insuficiente, o clave de servidor usada desde un navegador."],
  ["404", "No existe o no pertenece a tu cuenta. El mensaje es siempre el mismo para no revelar datos ajenos."],
  ["409", "Nonce repetido en una firma. Genera otro nonce y reintenta."],
  ["422", "La operación no es posible (saldo, límite, estado incorrecto). El mensaje explica el motivo."],
  ["429", "Demasiadas peticiones para tu cliente. Espera y reintenta con retroceso exponencial."],
  ["5xx", "Error del servidor. En operaciones que mueven dinero, reintenta con la misma Idempotency-Key."],
];

function Errores() {
  return (
    <>
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14, marginBottom: 16 }}>
        <thead><tr><th align="left" style={{ width: 70 }}>Código</th><th align="left">Significado y qué hacer</th></tr></thead>
        <tbody>{CODIGOS.map(([c, d]) => <tr key={c} style={{ borderTop: "1px solid #e2e8f0" }}><td><code>{c}</code></td><td>{d}</td></tr>)}</tbody>
      </table>
      <Bloque titulo="Error (JSON)" valor={{ error: "Saldo insuficiente" }} />
      <Bloque titulo="Listado paginado (JSON)" valor={{ movimientos: [{ id: 1041, fecha: "2026-11-01T09:12:00Z", importe: -18.9, concepto: "Compra" }], siguiente: 1040 }} />
      <p style={{ color: "#334155", marginTop: 14 }}>
        <strong>Idempotency-Key:</strong> genérala una vez por acción del usuario (por ejemplo, al pulsar «Confirmar»). Si la petición falla por red o por un 5xx, repítela con la misma clave: el movimiento no se duplica.
        Cada cliente tiene un límite de peticiones por minuto, configurado en el panel.
      </p>
    </>
  );
}

export function ExploradorApi() {
  const [spec, setSpec] = useState<Especificacion | null>(null);
  const [error, setError] = useState("");
  const [pestana, setPestana] = useState(PESTANAS[0]);
  const [busqueda, setBusqueda] = useState("");

  useEffect(() => {
    fetch("/openapi.json", { cache: "no-store" })
      .then((r) => { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
      .then((j: Especificacion) => setSpec(j))
      .catch(() => setError("No se ha podido cargar la documentación."));
  }, []);

  const operaciones = useMemo(() => (spec ? aplanar(spec) : []), [spec]);
  const contar = (p: string) => (p === "Todas" ? operaciones.length : operaciones.filter((o) => (o["x-grupo"] ?? "Usuario") === p).length);
  const filtradas = operaciones
    .filter((o) => pestana === "Todas" || (o["x-grupo"] ?? "Usuario") === pestana)
    .filter((o) => !busqueda || `${o.method} ${o.path} ${o.summary ?? ""}`.toLowerCase().includes(busqueda.toLowerCase()));
  const esListado = pestana !== "Webhooks" && pestana !== "Errores y límites";

  return (
    <div>
      <div role="tablist" style={{ display: "flex", gap: 6, flexWrap: "wrap", borderBottom: "1px solid #e2e8f0", marginBottom: 14 }}>
        {PESTANAS.map((p) => (
          <button key={p} role="tab" aria-selected={pestana === p} onClick={() => setPestana(p)}
            style={{ padding: "8px 12px", border: 0, borderBottom: pestana === p ? "3px solid #1d4ed8" : "3px solid transparent", background: "none", fontWeight: pestana === p ? 700 : 500, cursor: "pointer" }}>
            {p}{spec && esListadoPestana(p) ? ` (${contar(p)})` : ""}
          </button>
        ))}
      </div>
      {error && <p role="alert">{error}</p>}
      {!spec && !error && <p role="status">Cargando…</p>}
      {spec && pestana === "Webhooks" && <Webhooks spec={spec} />}
      {spec && pestana === "Errores y límites" && <Errores />}
      {spec && esListado && (
        <>
          <input type="search" placeholder="Buscar por ruta o descripción" value={busqueda} onChange={(e) => setBusqueda(e.target.value)}
            style={{ width: "100%", padding: 10, borderRadius: 8, border: "1px solid #cbd5e1", boxSizing: "border-box", marginBottom: 12 }} />
          {filtradas.length === 0 && <p style={{ color: "#64748b" }}>No hay operaciones en esta sección.</p>}
          {filtradas.map((o) => <Tarjeta key={o.method + o.path} op={o} />)}
        </>
      )}
    </div>
  );
}

function esListadoPestana(p: string): boolean {
  return p !== "Webhooks" && p !== "Errores y límites";
}
