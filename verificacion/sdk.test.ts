import { createHmac } from "node:crypto";
import { PlacetaServidor } from "/home/claude/proyecto/placeta-one/sdk/placeta-servidor";
import { PlacetaUsuario } from "/home/claude/proyecto/placeta-one/sdk/placeta-usuario";
import { PlacetaError, nuevaClaveIdempotencia } from "/home/claude/proyecto/placeta-one/sdk/placeta-core";

let fallos = 0;
const ok = (n: string, c: boolean, d = "") => { console.log(`${c ? "OK   " : "FALLO"} ${n}${d ? " — " + d : ""}`); if (!c) fallos++; };

type Llamada = { url: string; init: RequestInit };
let cola: Array<() => Response> = [];
const llamadas: Llamada[] = [];
(globalThis as any).fetch = async (url: string, init: RequestInit = {}) => {
  llamadas.push({ url: String(url), init });
  const f = cola.shift();
  return f ? f() : new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json" } });
};
const json = (status: number, cuerpo: unknown) => () => new Response(JSON.stringify(cuerpo), { status, headers: { "content-type": "application/json" } });

async function main() {
  // 1) Firma de sesión: el servidor verifica HMAC-SHA256(secreto, `${ts}.${cuerpo}`) en hex
  const secreto = "secreto-de-prueba-123";
  const srv = new PlacetaServidor("https://api.test", "plk_test", secreto);
  cola.push(json(201, { token: "pus_" + "a".repeat(64), expira: "x", permisos: ["me:read"] }));
  const s = await srv.crearSesion("12345678z", { minutos: 10, permisos: ["me:read"] });
  const l = llamadas.at(-1)!;
  const h = l.init.headers as Record<string, string>;
  const cuerpo = String(l.init.body);
  const esperada = createHmac("sha256", secreto).update(`${h["x-timestamp"]}.${cuerpo}`).digest("hex");
  ok("sesión: firma coincide con la que verifica el servidor", h["x-signature"] === esperada);
  ok("sesión: cabecera x-api-key con la clave", h["x-api-key"] === "plk_test");
  ok("sesión: nonce válido (16-64, base64url)", /^[A-Za-z0-9_-]{16,64}$/.test(h["x-nonce"]));
  ok("sesión: DIP normalizado en el cuerpo del SDK tal cual se envía", JSON.parse(cuerpo).dip === "12345678z" && JSON.parse(cuerpo).minutos === 10);
  ok("sesión: devuelve el token", s.token.startsWith("pus_"));

  // 2) Cada sesión usa nonce y firma distintos
  cola.push(json(201, { token: "pus_b", expira: "x", permisos: [] }));
  await srv.crearSesion("12345678z");
  const h2 = llamadas.at(-1)!.init.headers as Record<string, string>;
  ok("sesiones distintas: nonce distinto", h2["x-nonce"] !== h["x-nonce"]);

  // 3) Lectura: reintenta 500 y luego responde
  const u = new PlacetaUsuario("https://api.test", "pus_tok");
  cola.push(json(500, { error: "fallo" }), json(500, { error: "fallo" }), json(200, { cuentas: [{ iban: "PZ-1" }] }));
  const cuentas = await u.cuentas();
  ok("lectura: reintenta 5xx y devuelve el resultado", cuentas.length === 1 && cuentas[0].iban === "PZ-1");
  ok("lectura: Authorization con el token de usuario", (llamadas.at(-1)!.init.headers as Record<string, string>).authorization === "Bearer pus_tok");

  // 4) Escritura sin clave de idempotencia: NO reintenta
  llamadas.length = 0;
  cola.push(json(500, { error: "fallo" }));
  let err: unknown = null;
  try { await u.guardarBeneficiario("Mamá", "PZ-1"); } catch (e) { err = e; }
  ok("escritura sin Idempotency-Key: no reintenta", llamadas.length === 1 && err instanceof PlacetaError);

  // 5) Transferencia con clave: reintenta con la MISMA clave
  llamadas.length = 0;
  const clave = nuevaClaveIdempotencia();
  cola.push(json(503, { error: "caído" }), json(201, { transaccion: "tx-1" }));
  const r = await u.transferir({ desde_iban: "PZ-1", hacia_iban: "PZ-2", importe: 10 }, clave);
  const claves = llamadas.map((x) => (x.init.headers as Record<string, string>)["idempotency-key"]);
  ok("transferencia: reintenta con la misma Idempotency-Key", claves.length === 2 && claves[0] === clave && claves[1] === clave, `${claves.length} intentos`);
  ok("transferencia: devuelve la transacción", r.transaccion === "tx-1");

  // 6) Errores 422 no se reintentan y llegan con el mensaje del servidor
  llamadas.length = 0;
  cola.push(json(422, { error: "Fondos insuficientes" }));
  try { await u.transferir({ desde_iban: "PZ-1", hacia_iban: "PZ-2", importe: 1e9 }, nuevaClaveIdempotencia()); }
  catch (e) { err = e; }
  ok("422: no reintenta y conserva el mensaje", llamadas.length === 1 && err instanceof PlacetaError && (err as PlacetaError).mensaje === "Fondos insuficientes" && (err as PlacetaError).status === 422);

  // 7) IBAN en la URL: codificado, sin inyección de rutas
  llamadas.length = 0;
  cola.push(json(200, { iban: "x" }));
  await u.cuenta("PZ-1/../../otra");
  ok("IBAN codificado en la ruta", llamadas.at(-1)!.url.includes("PZ-1%2F..%2F..%2Fotra"), llamadas.at(-1)!.url);

  // 8) Parámetros de consulta vacíos no se envían
  llamadas.length = 0;
  cola.push(json(200, { movimientos: [], siguiente: null }));
  await u.movimientos("PZ-1", {});
  ok("consultas vacías no se añaden a la URL", !llamadas.at(-1)!.url.includes("?"), llamadas.at(-1)!.url);

  // 9) Clave de idempotencia: UUID v4
  ok("clave de idempotencia: UUID", /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(nuevaClaveIdempotencia()));

  console.log(fallos === 0 ? "\nSDK: todas las comprobaciones en OK." : `\nSDK: ${fallos} fallo(s).`);
  process.exit(fallos === 0 ? 0 : 1);
}
main();
