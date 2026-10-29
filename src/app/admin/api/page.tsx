"use client";
import { SCOPES, ENDPOINTS } from "@/lib/scopes";
const box = { background: "#fff", border: "1px solid #ddd", borderRadius: 10, padding: 16, marginBottom: 16 } as const;
export default function ApiDocs() {
  const base = typeof window !== "undefined" ? window.location.origin : "";
  return (<><h1>API para aplicaciones</h1>
    <section style={box}><h2>Cómo conectar una app</h2><ol><li>Bancos → Gestionar → <b>Claves de API</b> → «+ Nuevo»: elige los permisos y guarda la clave (se muestra una sola vez).</li>
      <li>La app envía la clave en la cabecera <code>x-api-key</code>. Las operaciones que mueven dinero exigen <code>Idempotency-Key</code>.</li><li>Cada clave solo ve y opera sobre su propia entidad.</li></ol>
      <pre style={{ background: "#f6f5f1", padding: 12, overflow: "auto" }}>{`curl -X POST ${base}/api/v1/transfers \\
  -H "x-api-key: plk_..." -H "Idempotency-Key: $(uuidgen)" -H "content-type: application/json" \\
  -d '{"from_iban":"PZ-0001-0002","to_iban":"PZ-0001-0003","amount":10.5,"memo":"Prueba"}'`}</pre></section>
    <section style={box}><h2>Endpoints</h2><table style={{ width: "100%", fontSize: 14 }}><tbody>{ENDPOINTS.map(([m, p, s]) => <tr key={m + p}><td><b>{m}</b></td><td><code>{p}</code></td><td><code>{s}</code></td></tr>)}</tbody></table></section>
    <section style={box}><h2>Permisos (scopes)</h2><table style={{ width: "100%", fontSize: 14 }}><tbody>{SCOPES.map(s => <tr key={s.k}><td><code>{s.k}</code></td><td>{s.l}</td></tr>)}</tbody></table></section>
    <section style={box}><h2>Códigos de respuesta</h2><p>401 clave ausente o inválida · 403 sin permiso o fuera de su entidad · 404 no encontrado · 422 regla de negocio (saldo, límite, etc.) · 429 límite de peticiones por minuto superado.</p></section></>);
}
