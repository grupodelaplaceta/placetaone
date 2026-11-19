# API para bancos: cómo construir la web o la app de tu entidad

Placeta One ofrece una API para que cada banco construya su propia web o app. Esta guía explica cómo funciona la seguridad, qué hace cada parte y cómo lo verificas tú.

## 1. El principio: ningún secreto llega al navegador

Un secreto que está en el navegador deja de ser secreto: cualquiera puede copiarlo. Por eso hay tres niveles, y solo uno de ellos puede salir del servidor.

| Nivel | Qué es | Dónde vive | Qué puede hacer |
|---|---|---|---|
| **Servidor del banco** | Clave `plk_…` + secreto de firma | Solo en tu backend (variables de entorno) | Crear sesiones de usuario y dar de alta usuarios en sus cuentas |
| **Sesión de usuario** | Token `pus_…` de 15 minutos (máximo 60) | En el navegador o la app del usuario | Ver solo sus cuentas y ordenar transferencias desde ellas |
| **Plataforma** | Comprobaciones en la base de datos | Servidor de Placeta One | Vuelve a comprobar, en cada operación, que la cuenta es del usuario |

Lo que garantiza el diseño:

- **Un usuario nunca puede indicar para quién actúa.** El usuario sale siempre del token. No existe un parámetro «usuario» que la API acepte.
- **Un token robado solo da acceso a las cuentas de ese usuario**, durante un tiempo corto, y se puede revocar.
- **Una clave robada no sirve sola**: para crear sesiones hace falta también el secreto de firma, y cada petición de servidor va firmada y solo vale una vez (nonce).
- **Las claves de servidor se rechazan desde navegadores**: cualquier petición con cabeceras de navegador (`Origin`, `Sec-Fetch-Site`) a una ruta de servidor responde 403.

Lo que **no** garantiza, y que tú debes cuidar: que tu backend guarde bien sus secretos, y que tu propia web no tenga fallos de programación. Esta API protege los datos de tus usuarios entre sí, no sustituye a tu seguridad interna.

## 1b. El DIP es el identificador del usuario

- **Una persona, un DIP.** El DIP identifica a la persona en toda la plataforma, en todas las entidades. Tu backend lo envía al crear la sesión o al vincular una cuenta. El navegador nunca lo recibe.
- **Formato.** Se aceptan letras y números de 5 a 20 caracteres. Los espacios y guiones se quitan y las letras pasan a mayúsculas: `12.345.678-z` se guarda como `12345678Z`.
- **Cada entidad ve solo sus cuentas.** Aunque una persona tenga cuentas en dos bancos, la sesión de un banco solo devuelve, consulta y mueve dinero desde las cuentas de ese banco.
- **Protección de datos.** El DIP es dato personal. Se guarda en claro solo en una tabla restringida al servicio. Los registros de auditoría solo contienen un hash con sal. Envíalo solo cuando tengas base legal para tratarlo, y minimiza: no lo guardes en tu navegador ni en tus logs.

## 2. Flujo completo

```
Usuario ──login (tu sistema)──▶ Tu backend
Tu backend ──POST /api/v1/sessions (clave + firma)──▶ Placeta One ──▶ token pus_… (15 min)
Tu backend ──devuelve el token al navegador/app del usuario──▶
Navegador/app ──GET /api/v1/me/accounts (Authorization: Bearer pus_…)──▶ Placeta One
Placeta One ──solo las cuentas de ese usuario──▶ Navegador/app
```

## 3. Alta de tu entidad (lo hace el personal de Placeta)

1. En **Panel → API**, crea un cliente para tu entidad. Se muestran **una sola vez** la clave `plk_…` y el **secreto de firma**. Guárdalos en tu backend.
2. Asigna los permisos del cliente. Para una app de usuario necesitas:
   - `sesiones:crear`: crear sesiones de usuario.
   - `usuarios:gestionar`: dar de alta a tus usuarios en sus cuentas.
   - `me:read` y `me:transfer`: lo que el usuario puede hacer con su sesión (el banco pide cuál, sin superar lo concedido).
3. Registra el origen de tu web (por ejemplo `https://app.tubanco.es`) para cada cliente. Sin origen registrado, el navegador no puede llamar a la API.
4. Vincula a cada usuario, por su DIP, con sus cuentas (sección 4).

Los permisos `accounts:read` y `transfers:write` de la API anterior son de **servidor a servidor**: no los uses en una web, porque abren toda la entidad.

## 4. Tu backend: vincular usuarios y crear sesiones

Vincular un usuario a una de tus cuentas (solo cuentas de tu entidad):

```ts
// servidor del banco
await fetch(`${BASE}/api/v1/bk/link-account`, {
  method: "POST",
  headers: { "content-type": "application/json", "x-api-key": process.env.PLACETA_CLAVE! },
  body: JSON.stringify({ dip: "12345678Z", iban: "PZ-0001-0002", rol: "holder" }),
});
```

Crear una sesión firmada (cada llamada firma `timestamp.cuerpo` con el secreto y usa un nonce nuevo):

```ts
import { createHmac, randomBytes } from "node:crypto";

export async function sesionParaUsuario(dip: string) {
  const cuerpo = JSON.stringify({ dip, minutos: 15, permisos: ["me:read", "me:transfer"] });
  const ts = Date.now();
  const firma = createHmac("sha256", process.env.PLACETA_FIRMA!).update(`${ts}.${cuerpo}`).digest("hex");
  const r = await fetch(`${process.env.PLACETA_BASE}/api/v1/sessions`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": process.env.PLACETA_CLAVE!,
      "x-timestamp": String(ts),
      "x-nonce": randomBytes(12).toString("base64url"),
      "x-signature": firma,
    },
    body: cuerpo,
  });
  if (!r.ok) throw new Error(`Sesión no creada (${r.status})`);
  return (await r.json()) as { token: string; expira: string; permisos: string[] };
}
```

Devuelve el `token` al navegador **solo tras haber autenticado al usuario en tu sistema**. No lo guardes en `localStorage`; mantenlo en memoria y renuévalo con tu backend cuando caduque.

## 5. Tu web o app: usar la sesión

El navegador o la app solo conoce el token del usuario. Nunca la clave ni el secreto.

```ts
const API = "https://api.placeta.example"; // dominio de Placeta One

export async function misCuentas(token: string) {
  const r = await fetch(`${API}/api/v1/me/accounts`, { headers: { authorization: `Bearer ${token}` } });
  if (!r.ok) throw new Error(`Error ${r.status}`);
  return (await r.json()).cuentas as { iban: string; nombre: string; saldo: number; disponible: number }[];
}

export async function transferir(token: string, desde: string, hacia: string, importe: number, concepto: string) {
  const r = await fetch(`${API}/api/v1/me/transfers`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "idempotency-key": crypto.randomUUID() },
    body: JSON.stringify({ desde_iban: desde, hacia_iban: hacia, importe, concepto }),
  });
  return { ok: r.ok, status: r.status, cuerpo: await r.json() };
}
```

Usa siempre `Idempotency-Key` en las transferencias: si la red falla y repites la petición, no se duplica el pago.

## 6. Referencia de endpoints

| Método y ruta | Quién lo llama | Permiso | Qué devuelve |
|---|---|---|---|
| `POST /api/v1/bk/link-account` | Servidor | `usuarios:gestionar` | Vincula un usuario (por su DIP) a una cuenta de tu entidad |
| `POST /api/v1/sessions` | Servidor (firmado) | `sesiones:crear` | Token `pus_…`, caducidad y permisos |
| `DELETE /api/v1/sessions` | Navegador/app | cualquier sesión | Revoca el token actual |
| `GET /api/v1/me/accounts` | Navegador/app | `me:read` | Solo las cuentas del usuario |
| `GET /api/v1/me/accounts/{iban}/transactions?antes=&limite=` | Navegador/app | `me:read` | Movimientos paginados (máximo 100) |
| `GET /api/v1/me/accounts/{iban}/receipts` | Navegador/app | `me:read` | Recibos fiscales de la cuenta |
| `POST /api/v1/me/transfers` | Navegador/app | `me:transfer` | Transferencia desde una cuenta del usuario. Requiere `Idempotency-Key` |

Una cuenta que no es del usuario responde **404**, igual que una que no existe: así no se puede averiguar qué cuentas hay.

Errores: `401` sesión ausente, caducada o revocada; `403` permiso insuficiente; `409` petición repetida (nonce); `429` demasiadas peticiones; `422` la operación no se puede hacer (por ejemplo, fondos insuficientes).

## 7. Verificar el aislamiento antes de publicar

El script `scripts/aislamiento.mjs` comprueba los puntos críticos con dos usuarios reales de tu entidad:

```bash
BASE=https://tu-entorno CLAVE=plk_... FIRMA=... IBAN_A=PZ-... IBAN_B=PZ-... node scripts/aislamiento.mjs
```

Ejecútalo en un entorno de pruebas antes de cada publicación. Debe terminar con todas las comprobaciones en OK.

## 8. Lista de verificación antes de publicar tu web o app

- [ ] La clave `plk_…` y el secreto de firma solo están en el backend, nunca en el código del navegador ni en el repositorio público.
- [ ] El token `pus_…` no se guarda en `localStorage` ni en cookies sin `HttpOnly`.
- [ ] El backend crea la sesión **después** de autenticar al usuario en tu sistema.
- [ ] Renuevas la sesión desde el backend, no desde el navegador.
- [ ] Las transferencias llevan `Idempotency-Key` única por intento.
- [ ] El origen de tu web está aprobado para tu cliente (`/api/v1/bk/origenes`); ningún otro dominio recibe CORS.
- [ ] `scripts/aislamiento.mjs` termina sin fallos en el entorno de pruebas.
- [ ] Rotas la clave y el secreto si sospechas que se han filtrado (ver sección 9).

## 9. Qué hacer si algo se filtra

- **Se filtra un token de usuario:** sus efectos caducan en 15 minutos como máximo. Ciérralo desde tu backend con `DELETE /api/v1/sessions`.
- **Se filtra la clave `plk_…` o el secreto de firma:** crea un cliente nuevo en el panel, cambia tu backend al cliente nuevo y desactiva el anterior. La firma depende del secreto, así que ambos se rotan juntos.
- **Sospechas de un acceso indebido:** el registro de auditoría guarda cada sesión abierta con su usuario de plataforma, y cada transferencia con su clave de idempotencia.

## 10. Límites conocidos

- El aislamiento es **por usuario y cuenta**, comprobado en cada petición. No hay roles dentro de un mismo usuario más allá de los de cada cuenta (titular, cotitular, autorizado).
- Los límites de peticiones son **por cliente**, no por usuario. Un cliente comprometido puede consumir su cuota, aunque no ver datos ajenos.
- Un usuario que hace login en tu sistema con la contraseña de otro lo tiene todo: la plataforma confía en la autenticación de tu banco. Esa parte es tuya.
- Los orígenes de navegador los registra el personal de Placeta, no el banco.
- El DIP se acepta con formato alfanumérico de 5 a 20 caracteres. Si el DIP real de tu país tiene otro formato, la validación debe ajustarse antes de publicar.
- Una persona vinculada en dos bancos tiene dos conjuntos de cuentas, pero un único identificador. Cada banco solo ve las suyas.
