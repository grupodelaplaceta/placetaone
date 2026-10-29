// Prueba de aislamiento entre usuarios de un mismo banco.
// Antes de ejecutarla: vincula IBAN_A al DIP de A y IBAN_B al DIP de B con POST /api/v1/bk/link-account.
// Uso: BASE=https://tu-dominio CLAVE=plk_... FIRMA=<secreto> IBAN_A=... IBAN_B=... DIP_A=... DIP_B=... node scripts/aislamiento.mjs
// Código de salida: 0 si todo se cumple, 1 si alguna comprobación falla.
import { createHmac, randomBytes } from "node:crypto";

const { BASE, CLAVE, FIRMA, IBAN_A, IBAN_B, DIP_A, DIP_B } = process.env;
if (!BASE || !CLAVE || !FIRMA || !IBAN_A || !IBAN_B || !DIP_A || !DIP_B) {
  console.error("Faltan variables: BASE, CLAVE, FIRMA, IBAN_A, IBAN_B, DIP_A, DIP_B");
  process.exit(2);
}

let fallos = 0;
const comprobar = (nombre, cumple, detalle = "") => {
  console.log(`${cumple ? "OK   " : "FALLO"} ${nombre}${detalle ? ` (${detalle})` : ""}`);
  if (!cumple) fallos++;
};

// Crea una sesión de usuario firmada. Devuelve el estado y el cuerpo de la respuesta.
async function crearSesion(dip, nonce = randomBytes(12).toString("base64url")) {
  const cuerpo = JSON.stringify({ dip, minutos: 5 });
  const ts = Date.now();
  const firma = createHmac("sha256", FIRMA).update(`${ts}.${cuerpo}`).digest("hex");
  const r = await fetch(`${BASE}/api/v1/sessions`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-client-key": CLAVE, "x-timestamp": String(ts), "x-nonce": nonce, "x-signature": firma },
    body: cuerpo,
  });
  return { status: r.status, json: await r.json().catch(() => ({})), nonce };
}

const get = (ruta, token) => fetch(`${BASE}${ruta}`, { headers: token ? { authorization: `Bearer ${token}` } : {} });
const json = async (r) => r.json().catch(() => ({}));

const sa = await crearSesion(DIP_A);
const sb = await crearSesion(DIP_B);
comprobar("sesión del usuario A se crea", sa.status === 201);
comprobar("sesión del usuario B se crea", sb.status === 201);
const tokA = sa.json.token, tokB = sb.json.token;

// Acceso sin credenciales
comprobar("sin token no hay acceso a /me", (await get("/api/v1/me/accounts")).status === 401);
comprobar("token inventado no hay acceso", (await get("/api/v1/me/accounts", "pus_" + "0".repeat(64))).status === 401);

// Cada usuario solo ve sus cuentas
const listaA = (await json(await get("/api/v1/me/accounts", tokA))).cuentas ?? [];
const listaB = (await json(await get("/api/v1/me/accounts", tokB))).cuentas ?? [];
const ibansA = listaA.map((c) => c.iban), ibansB = listaB.map((c) => c.iban);
comprobar("A ve su cuenta", ibansA.includes(IBAN_A));
comprobar("A no ve la cuenta de B", !ibansA.includes(IBAN_B));
comprobar("B no ve la cuenta de A", !ibansB.includes(IBAN_A));

// Lectura de cuentas ajenas: 404 (no se revela que existan)
comprobar("A no lee movimientos de B", (await get(`/api/v1/me/accounts/${IBAN_B}/transactions`, tokA)).status === 404);
comprobar("A no lee recibos de B", (await get(`/api/v1/me/accounts/${IBAN_B}/receipts`, tokA)).status === 404);

// Escritura desde cuenta ajena: rechazada
const intento = await fetch(`${BASE}/api/v1/me/transfers`, {
  method: "POST",
  headers: { authorization: `Bearer ${tokA}`, "content-type": "application/json", "idempotency-key": randomBytes(8).toString("hex") },
  body: JSON.stringify({ desde_iban: IBAN_B, hacia_iban: IBAN_A, importe: 1, concepto: "prueba de aislamiento" }),
});
comprobar("A no puede transferir desde la cuenta de B", intento.status !== 201, `estado ${intento.status}`);

// La clave de servidor no funciona desde un navegador
const desdeNavegador = await fetch(`${BASE}/api/v1/accounts`, { headers: { "x-api-key": CLAVE, origin: "https://tienda.ejemplo" } });
comprobar("la clave de servidor se rechaza con cabecera de navegador", desdeNavegador.status === 403, `estado ${desdeNavegador.status}`);

// Firma incorrecta y nonce repetido
const ts = Date.now(), cuerpo = JSON.stringify({ dip: DIP_A });
const firmaMala = await fetch(`${BASE}/api/v1/sessions`, { method: "POST", headers: { "content-type": "application/json", "x-client-key": CLAVE, "x-timestamp": String(ts), "x-nonce": randomBytes(12).toString("base64url"), "x-signature": "0".repeat(64) }, body: cuerpo });
comprobar("firma incorrecta se rechaza", firmaMala.status === 401);
const repetido = await crearSesion(DIP_A, sa.nonce);
comprobar("nonce repetido se rechaza", repetido.status === 409, `estado ${repetido.status}`);

// Orígenes de navegador: solo los registrados
const preflightMalo = await fetch(`${BASE}/api/v1/me/accounts`, { method: "OPTIONS", headers: { origin: "https://no-autorizado.ejemplo", "access-control-request-method": "GET" } });
comprobar("origen no registrado no obtiene CORS", preflightMalo.status === 403, `estado ${preflightMalo.status}`);

// Cerrar sesión revoca el acceso
await fetch(`${BASE}/api/v1/sessions`, { method: "DELETE", headers: { authorization: `Bearer ${tokA}` } });
comprobar("tras cerrar sesión el token deja de valer", (await get("/api/v1/me/accounts", tokA)).status === 401);

console.log(fallos === 0 ? "\nTodas las comprobaciones se cumplen." : `\n${fallos} comprobación(es) fallan.`);
process.exit(fallos === 0 ? 0 : 1);
