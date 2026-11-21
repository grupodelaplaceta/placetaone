# API de Placeta One: qué es cada una y cómo implementarla en un banco

> **Documento para los equipos técnicos de las entidades.** Describe las APIs de Placeta One, para qué sirve cada familia, cómo se autentica cada llamada, qué debe hacer tu banco y qué no debes hacer. El catálogo completo se genera desde el contrato `docs/openapi.json` y está al final.

**Versión:** 1.0 (borrador para revisión) · **Fecha:** 21/11/2026 · **Responsable técnico:** Mikel Alegre (DIP-23749931M)

---

## 1. Resumen: cinco familias de API

| Familia | Ruta base | Quién la usa | Cómo se autentica | Para qué |
|---|---|---|---|---|
| **Banca** | `/api/v1/bk/...` | El servidor de tu banco | Clave `x-api-key` y permiso concreto | Gestionar clientes, cuentas, empresas, pasarela, subvenciones y nóminas |
| **Sesiones** | `/api/v1/sessions` | El servidor de tu banco | Clave, **firma HMAC**, marca de tiempo y nonce | Crear una sesión de usuario (token de 15 minutos) |
| **Usuario** | `/api/v1/me/...` | La web o la app de tu usuario | Token de sesión `pus_…` (`Authorization: Bearer`) | Ver cuentas, transferir, canjear bonos, pagar deudas |
| **Pública** | `/api/checkout/{token}`, `/api/public-config` | Navegadores (pagos y configuración) | Token de un solo pago, o sin autenticación (solo configuración pública) | Página de pago y configuración pública |
| **Webhooks (salientes)** | Tu URL | Placeta One te llama a ti | Firma HMAC-SHA256 en `x-placeta-signature` | Avisarte de eventos (pagos, nóminas) |

Hay además rutas de **administración** (panel de la Junta) y de **cron** (procesos internos). **No son para bancos**: no las llames ni las implementes.

---

## 2. Antes de empezar

1. **Alta de tu entidad.** Lo hace el personal de Placeta One. Recibes un identificador de entidad, una **clave de cliente** (`plk_…`) y un **secreto de firma**.
2. **Dónde guardar los secretos.** La clave y el secreto de firma viven **solo en el servidor de tu banco**, en variables de entorno o en un gestor de secretos. Nunca en el navegador, en una app móvil ni en el repositorio.
3. **Permisos.** Cada clave tiene una lista de permisos (`scopes`), y cada operación exige uno. Sin el permiso adecuado, la respuesta es `403`. Pide solo los que tu integración necesita.
4. **Entornos.** Trabaja primero en el **entorno de pruebas**. Pasa a producción solo cuando tus pruebas den el resultado esperado.
5. **Límite de peticiones.** Cada clave tiene un límite por minuto. Un cliente nuevo arranca con **60 por minuto** (ajuste `api_default_rate_limit`).

---

## 3. Cabeceras y formato

| Cabecera | Cuándo | Qué es |
|---|---|---|
| `x-api-key` | Todas las rutas de banca y sesiones | Tu clave de cliente |
| `x-timestamp` | Solo `/api/v1/sessions` | Marca de tiempo en milisegundos (`Date.now()`). Debe estar a menos de **5 minutos** del reloj del servidor |
| `x-nonce` | Solo `/api/v1/sessions` | Identificador **único** de cada petición: entre 16 y 64 caracteres (`A-Z`, `a-z`, `0-9`, `_`, `-`). Una petición repetida se rechaza |
| `x-signature` | Solo `/api/v1/sessions` | HMAC-SHA256 en hexadecimal de `timestamp + "." + cuerpo exacto`, con tu secreto de firma |
| `authorization` | Rutas de usuario (`/api/v1/me/...`) | `Bearer pus_…` (token de sesión del usuario) |
| `idempotency-key` | Operaciones que mueven dinero (sección 6) | Identificador que generas tú, para que un reintento no duplique el movimiento |
| `content-type` | Cuando hay cuerpo | `application/json` |

**Formato.** Las respuestas son JSON. Los importes van en **Placetas (Pz)**, como número con decimales. Las fechas, en **ISO 8601**: `AAAA-MM-DD` o `AAAA-MM-DDTHH:MM`.

**Errores.** Llegan como `{ "error": "mensaje" }` con el código HTTP correspondiente (sección 7).

---

## 4. Autenticación: los tres niveles

El diseño separa **quién eres** (tu banco), **para quién actúas** (un usuario) y **qué puedes hacer** (un permiso).

### 4.1 Tu servidor: clave

Cada llamada de banca lleva `x-api-key`. El sistema busca la clave, comprueba que está activa, que tu cliente tiene el **permiso** que pide la ruta, y que no has superado tu límite por minuto.

**Importante:** las rutas de banca **no exigen firma**. Solo `/api/v1/sessions` la exige. El resto solo comprueba la clave y el permiso. Ver la sección 12 antes de dar nada por seguro.

Las claves de servidor **no se pueden usar desde un navegador**: si la petición lleva cabeceras de navegador (`Origin` o `Sec-Fetch-Site`), se rechaza con `403`. Así una clave no acaba en el código de tu web.

### 4.2 Sesión de usuario: token

Para que un usuario use la API de usuario, tu servidor **crea una sesión** a su nombre con `POST /api/v1/sessions`. La respuesta es un token `pus_…` válido **15 minutos** (puedes pedir entre 1 y 60). El usuario **no puede indicar para quién actúa**: viene siempre del token.

Un token solo da acceso a las cuentas de ese usuario, y solo con los permisos concedidos en la sesión.

### 4.3 Permisos

**De cliente** (en tu clave): los que la Junta te haya concedido. Son el límite máximo.

**De usuario** (al crear la sesión): solo se pueden conceder los de esta lista **y** que tu clave tenga:

| Permiso | Qué permite al usuario |
|---|---|
| `me:read` | Ver sus cuentas, movimientos y saldos |
| `me:transfer` | Hacer transferencias y pagar deudas |
| `me:contratar` | Contratar productos (por ejemplo, un diseño de tarjeta) |
| `me:seguridad` | Gestión de seguridad de su cuenta |
| `me:disputas` | Disputar deudas |

Los permisos que no existan o que tu clave no tenga se ignoran. Si no queda ninguno, la sesión se rechaza con `403`.

---

## 5. Flujo de sesión de usuario

```text
Tu web/app          Tu servidor (banco)                       Placeta One
   |                       |                                         |
   |-- login del usuario ->|                                         |
   |                       |-- POST /api/v1/sessions (firmada) ----->|
   |                       |<-------- 201 { token, expira, permisos }|
   |<-- token (en memoria)-|                                         |
   |-- GET /api/v1/me/accounts  (Bearer pus_...) ------------------->|
   |<------------------------------------------- 200 cuentas --------|
```

**Paso 1. Autentica al usuario en tu sistema.** Solo después creas la sesión: Placeta One confía en que tu banco ya ha comprobado la identidad.

**Paso 2. Crea la sesión desde tu servidor, firmada:**

```ts
// Servidor del banco (Node.js). Nunca desde el navegador.
import { createHmac, randomBytes } from "node:crypto";

export async function sesionParaUsuario(dip: string) {
  const cuerpo = JSON.stringify({ dip, minutos: 15, permisos: ["me:read", "me:transfer"] });
  const ts = Date.now();
  const firma = createHmac("sha256", process.env.PLACETA_FIRMA!)
    .update(`${ts}.${cuerpo}`)               // la firma cubre la marca de tiempo y el cuerpo EXACTO
    .digest("hex");
  const r = await fetch(`${process.env.PLACETA_BASE}/api/v1/sessions`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": process.env.PLACETA_CLAVE!,
      "x-timestamp": String(ts),
      "x-nonce": randomBytes(12).toString("base64url"),   // nuevo en cada petición
      "x-signature": firma,
    },
    body: cuerpo,                             // el mismo texto que se ha firmado
  });
  if (!r.ok) throw new Error(`Sesión no creada (${r.status})`);
  return (await r.json()) as { token: string; expira: string; permisos: string[] };
}
```

**Respuesta correcta (201):** `{ "token": "pus_…", "expira": "…", "permisos": ["me:read", "me:transfer"] }`.

**Paso 3. Entrega el token al navegador o a la app.** Solo tras autenticar al usuario, y **sin guardarlo en `localStorage`**: mantenlo en memoria. Cuando caduque, pide otra sesión a tu servidor. Hoy no hay renovación desde el lado del usuario (sección 12).

**Paso 4. Usa el token** en las rutas `/api/v1/me/...`.

**Cerrar sesión.** La sesión se revoca con su token. Haz esta llamada cuando el usuario salga de tu web.

### Qué debe comprobar tu servidor antes de firmar

- Que el usuario está autenticado y es quien dice ser.
- Que pides **solo los permisos que necesita** (nunca `me:transfer` para una pantalla de solo consulta).
- Que registras el **nonce** y la **marca de tiempo** para depurar, sin registrar nunca el secreto.

---

## 6. Idempotencia: cómo no duplicar un movimiento

Cuando una conexión se corta, no sabes si la operación se hizo. La solución es la **clave de idempotencia**: un identificador que generas tú y reutilizas en los reintentos.

| Operación | Cabecera | Formato de la clave | Qué pasa si la repites |
|---|---|---|---|
| Transferencia de usuario (`POST /api/v1/me/transfers`) | `idempotency-key` **obligatoria** | Hasta 128 caracteres | Si los datos son iguales, devuelve la transacción original. Si cambian, falla |
| Pago de deuda (`POST /api/v1/me/deudas/{id}/pagar`) | `Idempotency-Key` **obligatoria** | 8 a 80 caracteres: `A-Z`, `a-z`, `0-9`, `_`, `-` | No suma el pago dos veces |
| Compra de diseño de tarjeta | `Idempotency-Key` **obligatoria** | Según la ruta | Igual que las anteriores |

**Reglas:**
- Genera una clave **nueva por cada operación de negocio** (por ejemplo, `crypto.randomUUID()`), y reutiliza **la misma** solo en sus reintentos.
- No reutilices una clave para otra operación: el sistema la rechaza si los datos no coinciden.
- Guarda la clave junto con la operación en tu base de datos **antes** de llamar a Placeta One.

```ts
// Transferencia con idempotencia (desde la web del usuario, con su token)
const clave = crypto.randomUUID();   // guárdala antes de llamar; reutilízala en los reintentos
const r = await fetch(`${API}/api/v1/me/transfers`, {
  method: "POST",
  headers: { authorization: `Bearer ${token}`, "content-type": "application/json", "idempotency-key": clave },
  body: JSON.stringify({ desde_iban: "PZ-0001-0002", hacia_iban: "PZ-0002-0100", importe: 25, concepto: "Cena" }),
});
// 201 → { transaccion: "…" }. Si no hay respuesta, reintenta con LA MISMA clave.
```

**Campos de la transferencia de usuario:** `desde_iban` (cuenta del usuario), `hacia_iban`, `importe` (mayor que cero) y `concepto` (hasta 200 caracteres, opcional).

---

## 7. Errores y códigos HTTP

| Código | Significado | Qué hacer |
|---|---|---|
| **400** | Petición mal formada: falta un campo, formato de fecha o de clave incorrecto | Corrige la petición. No reintentes igual |
| **401** | Clave no válida o inactiva, token caducado, firma o marca de tiempo no válidas | Revisa la clave, el reloj del servidor y el cálculo de la firma. Pide sesión nueva si el token caducó |
| **403** | La clave no tiene el permiso, la petición viene de un navegador, o el permiso de usuario no está concedido | Pide el permiso a la Junta, o cambia la integración |
| **404** | El recurso no existe en tu entidad. La API nunca muestra datos de otra entidad | Comprueba el identificador |
| **409** | Conflicto: el recurso ya existe o el estado no lo permite | Lee el mensaje y consulta el estado antes de reintentar |
| **422** | Regla de negocio: sin fondos, fuera de presupuesto, sin permiso sobre el recurso… | Lee el mensaje. Es una decisión de negocio, no un fallo técnico |
| **429** | Has superado el límite de peticiones por minuto | Espera y reduce la frecuencia |
| **5xx** | Error del servidor | Reintenta con la **misma clave de idempotencia**, con espera creciente |

**Reglas de oro:**
- Un `422` no se arregla reintentando: se arregla cambiando los datos o el estado.
- Ante un `5xx` o un corte, reintenta **con la misma clave**. Nunca con una nueva.
- Registra el mensaje de error y la hora para cualquier investigación.

---

## 8. Límites de peticiones

- Cada clave tiene un límite **por minuto**. Al superarlo, la API responde `429`.
- El límite lo fija la Junta por cliente. Por defecto, **60 por minuto**.
- Las lecturas repetidas (por ejemplo, consultar el saldo cada segundo) consumen el mismo límite: **cachea** en tu servidor.
- No hagas sondeo de eventos: usa los **webhooks** (sección 9).

---

## 9. Webhooks: recibir avisos de Placeta One

Un webhook es una llamada que Placeta One te hace a **tu URL** cuando pasa algo. Así no tienes que preguntar constantemente.

### 9.1 Darlo de alta

Llama a `POST /api/v1/bk/webhooks` con tu URL (**https** obligatoria) y la lista de eventos, o `["*"]` para todos. La respuesta incluye el **secreto del webhook**: guárdalo en tu servidor. Se muestra **una sola vez**.

Puedes **rotar** el secreto (`POST /api/v1/bk/webhooks/{id}/rotar`), ver las **entregas** y **reintentar** las fallidas.

### 9.2 Eventos

Los eventos que documenta el contrato y se emiten en el sistema:

| Evento | Cuándo se envía |
|---|---|
| `checkout.pagado` | Un pago de la pasarela se ha completado |
| `checkout.rechazado` | Un pago de la pasarela ha sido rechazado |
| `checkout.cancelado` | Un pago de la pasarela se ha cancelado |
| `checkout.confirmacion_requerida` | El pago necesita confirmación adicional |
| `nomina.pagada` | Se ha pagado una nómina del periodo |
| `transaction.posted` | Se ha registrado un movimiento |

_Nota:_ la lista definitiva de eventos la confirma la base de datos del proyecto. Antes de depender de un evento que no aparezca aquí, pregunta a la Junta.

### 9.3 Verificar cada entrega (obligatorio)

Cada entrega lleva la cabecera **`x-placeta-signature`**: el HMAC-SHA256 en hexadecimal del **cuerpo exacto**, con el secreto de tu webhook. **Verifica la firma antes de actuar.**

```ts
import { createHmac, timingSafeEqual } from "node:crypto";

export function entregaValida(cuerpoCrudo: string, firma: string, secreto: string): boolean {
  const esperada = createHmac("sha256", secreto).update(cuerpoCrudo).digest("hex");
  return firma.length === esperada.length &&
         timingSafeEqual(Buffer.from(firma), Buffer.from(esperada));
}
```

**Importante:** calcula la firma sobre el **cuerpo tal como llegó**, antes de parsearlo como JSON. Si lo parseas y lo vuelves a serializar, la firma no coincidirá.

### 9.4 Reintentos

Si tu servidor no responde con éxito, Placeta One reintenta hasta el número de intentos configurado (por defecto **5**). Responde **rápido** y procesa lo pesado en segundo plano. Haz tu proceso **idempotente**: el mismo evento puede llegar dos veces.

---

## 10. Recetas por caso de uso

### 10.1 Dar de alta un cliente y vincularlo a una cuenta

1. Crea o localiza el cliente: `POST /api/v1/bk/clientes`.
2. Crea la cuenta: `POST /api/v1/bk/cuentas`, o usa una existente de tu entidad.
3. Vincula al usuario con su cuenta: `POST /api/v1/bk/link-account` con `{ "dip", "iban", "rol" }`. El rol por defecto es `holder` (titular).

Solo puedes vincular cuentas **de tu entidad**: cualquier otro IBAN responde `404`.

### 10.2 Cobrar con la pasarela

1. Crea el cobro: `POST /api/v1/bk/checkouts` con `origen`, `client_ref`, `dip`, `iban_destino`, `importe`, `concepto` y, si procede, `iban_pagador` o `tarjeta_ref`. Recibes un código `PAG-…`.
2. Muestra el código al pagador. El pagador lo introduce en **su** banco.
3. Tu banco, como pagador, **canjea** el código: `POST /api/v1/bk/pagos/canjear`.
4. Tu banco **aprueba o rechaza**: `POST /api/v1/bk/pagos/{id}/resolucion`.
5. Escucha `checkout.pagado` o `checkout.rechazado` por webhook. No des el pago por bueno solo por la respuesta del navegador.

### 10.3 Crear una empresa y su organigrama

1. Da de alta la empresa: `POST /api/v1/bk/empresas`.
2. Añade su primera cuenta de empresa: `POST /api/v1/bk/empresas/{id}/cuentas` con `{ "iban" }`. Eso crea su **CIP** (entidad institucional) y su organigrama inicial.
3. Crea unidades: `POST /api/v1/bk/organigrama` con `accion: unidad` y `dip_actor` = DIP del **titular**. Si no indicas unidad superior, cuelga de la Junta raíz.
4. Consulta la ficha: `GET /api/v1/bk/empresas/{id}`.

> Sin el `dip_actor` correcto, la API responde «Sin permiso para cambiar el organigrama».

### 10.4 Complementos de actividad y nómina

1. Crea el catálogo: `POST /api/v1/bk/empresas/{id}/complementos`.
2. Asigna a un contrato: `POST .../complementos/asignaciones` (sin importe, se usa el importe base).
3. Revisa los conceptos del mes: `GET .../nomina/conceptos?periodo=AAAA-MM`.
4. Paga el periodo: `POST /api/v1/bk/nominas/periodos`. **Es idempotente**: repetir no paga dos veces.
5. Descarga recibos: `GET .../nomina/recibos?periodo=AAAA-MM` (JSON), o con `dip=…&formato=pdf`.

> Quien asigna un complemento o autoriza un salario no puede ejecutar la nómina de ese periodo.

### 10.5 Convocatorias y subvenciones

1. La empresa abre la convocatoria: `POST /api/v1/bk/empresas/{id}/convocatorias`. Un **bono exige** fecha de caducidad.
2. Concede: `POST .../convocatorias/{conv}/concesiones`. Se **reserva** el importe. No se puede conceder a una cuenta de la propia empresa.
3. Cierra cuando proceda: `POST .../convocatorias/{conv}/cerrar`.
4. Justificaciones: `POST /api/v1/bk/justificaciones/{id}/pagar` o `.../rechazar`.
5. Reversiones: `POST /api/v1/bk/subvenciones/{id}/revertir` con un motivo de 10 caracteres o más.
6. Informe: `GET /api/v1/bk/subvenciones/{id}/informe` (JSON, o `formato=pdf`).

### 10.6 RBU y deudas del usuario

- **RBU:** el usuario lista sus bonos (`GET /api/v1/me/rbu`), canjea uno (`POST /api/v1/me/rbu/{id}/claim`) o consulta su saldo prepago (`GET /api/v1/me/rbu/saldo`). Un bono sin canjear caduca a los 3 meses.
- **Deudas:** `GET /api/v1/me/deudas`, pago con `Idempotency-Key`, y disputa dentro de los 60 días desde el vencimiento.

---

## 11. Catálogo completo de operaciones

Generado desde `docs/openapi.json`: **164 operaciones** en **138 rutas**. Lo que aparece aquí es lo que documenta el contrato público.

### 11.1 Banca (`/api/v1/bk`): 111 operaciones

Permisos que usa la banca: `accounts:read`, `branding:gestionar`, `checkout:crear`, `clientes:gestionar`, `comisiones:configurar`, `convocatorias:gestionar`, `disputas:gestionar`, `empresas:gestionar`, `entidad:configurar`, `gastos:gestionar`, `interbancarias:gestionar`, `nominas:generar`, `nominas:read`, `organigrama:gestionar`, `organigrama:leer`, `origenes:gestionar`, `pagos:resolver`, `pagos:restringir`, `pasarela:configurar`, `personas:buscar`, `planes:read`, `politicas:gestionar`, `presupuestos:gestionar`, `presupuestos:leer`, `recurrentes:gestionar`, `retribuciones:gestionar`, `solicitudes:gestionar`, `subvenciones:gestionar`, `tareas:gestionar`, `tarjetas:cobrar`, `tarjetas:gestionar`, `tasas:gestionar`, `usuarios:gestionar`, `webhooks:gestionar`.

### Banco (servidor) (6)

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/v1/bk/cuentas` | `accounts:read` | Cuentas de mi entidad con saldo disponible |
| POST | `/api/v1/bk/link-account` | `usuarios:gestionar` | Vincular un usuario (DIP) a una cuenta de la entidad |
| DELETE | `/api/v1/bk/origenes` | `origenes:gestionar` | Retirar un origen |
| GET | `/api/v1/bk/origenes` | `origenes:gestionar` | Listar los orígenes de navegador de tu cliente |
| POST | `/api/v1/bk/origenes` | `origenes:gestionar` | Solicitar un origen (queda pendiente de aprobación) |
| GET | `/api/v1/bk/personas` | `personas:buscar` | Buscar por DIP las cuentas de la entidad |

### Cuenta institucional (59)

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/v1/bk/branding` | `branding:gestionar` | Ver la identidad visual de mi entidad en la ventana de pago |
| PUT | `/api/v1/bk/branding` | `branding:gestionar` | Fijar el nombre, logo, color y texto legal de mi entidad |
| POST | `/api/v1/bk/branding/logo` | `branding:gestionar` | Subir el logo de mi entidad |
| GET | `/api/v1/bk/clientes` | `clientes:gestionar` | Claves de API de mi entidad (sin claves) |
| POST | `/api/v1/bk/clientes` | `clientes:gestionar` | Crear una clave de API para mi entidad |
| POST | `/api/v1/bk/clientes/{id}/desactivar` | `clientes:gestionar` | Desactivar una clave de API de mi entidad |
| POST | `/api/v1/bk/clientes/{id}/rotar` | `clientes:gestionar` | Rotar la clave de una clave de API de mi entidad |
| GET | `/api/v1/bk/comisiones` | `comisiones:configurar` | Ver la política de comisiones del banco y la tarifa del propietario |
| PUT | `/api/v1/bk/comisiones` | `comisiones:configurar` | Decidir quién paga la comisión interbancaria para cuentas o tarjetas |
| POST | `/api/v1/bk/convocatorias` | `convocatorias:gestionar` | Abrir una convocatoria interna de financiación |
| GET | `/api/v1/bk/disputas` | `disputas:gestionar` | Reclamaciones de deudas que afectan a mi entidad (como acreedor o como deudor) |
| POST | `/api/v1/bk/disputas/{id}/resolver` | `disputas:gestionar` | Resolver una reclamación como banco acreedor |
| GET | `/api/v1/bk/empresas` | `empresas:gestionar` | Listar las empresas de mi entidad |
| POST | `/api/v1/bk/empresas` | `empresas:gestionar` | Dar de alta una empresa con su titular inicial y sus cuentas de empresa |
| GET | `/api/v1/bk/empresas/{id}` | `empresas:gestionar` | Ficha de una empresa: titulares, cuentas, pasarela y versión del contrato |
| POST | `/api/v1/bk/empresas/{id}/asegurar-entidad` | `empresas:gestionar` | Crear o reutilizar la entidad institucional de la empresa |
| GET | `/api/v1/bk/empresas/{id}/contrato` | `empresas:gestionar` | Contrato vigente de la empresa (sin claves) |
| POST | `/api/v1/bk/empresas/{id}/cuentas` | `empresas:gestionar` | Añadir una cuenta a la empresa |
| PUT | `/api/v1/bk/empresas/{id}/datos` | `empresas:gestionar` | Corregir nombre e identificador (CIP) de la empresa |
| POST | `/api/v1/bk/empresas/{id}/entidad` | `empresas:gestionar` | Vincular la entidad institucional (CIP) a la empresa |
| POST | `/api/v1/bk/empresas/{id}/entidad/crear` | `empresas:gestionar` | Crear la entidad institucional de la empresa sobre una de sus cuentas y vincularla |
| POST | `/api/v1/bk/empresas/{id}/estado` | `empresas:gestionar` | Activar, suspender o dar de baja una empresa |
| GET | `/api/v1/bk/empresas/{id}/ficha` | `empresas:gestionar` | Ficha completa de la empresa: entidad, organigrama, presupuesto por departamento y nóminas |
| POST | `/api/v1/bk/empresas/{id}/pasarela` | `empresas:gestionar` | Dar de alta la pasarela de la empresa: su cliente de API y su contrato |
| POST | `/api/v1/bk/empresas/{id}/pasarela/rotar` | `empresas:gestionar` | Rotar la clave de la pasarela de una empresa. La anterior deja de valer |
| POST | `/api/v1/bk/empresas/{id}/titulares` | `empresas:gestionar` | Dar de alta un titular, autorizado o lector en la empresa |
| POST | `/api/v1/bk/empresas/{id}/titulares/cese` | `empresas:gestionar` | Dar de baja a un titular de la empresa |
| PUT | `/api/v1/bk/entidad/configuracion` | `entidad:configurar` | Activar solicitudes de unidades y fijar la doble firma de la entidad |
| GET | `/api/v1/bk/expedientes` | `retribuciones:gestionar` | Expediente de una persona en la entidad: puestos, retribuciones, tareas y nóminas |
| POST | `/api/v1/bk/fondos` | `presupuestos:gestionar` | Crear un fondo restringido a una finalidad |
| POST | `/api/v1/bk/gastos` | `gastos:gestionar` | Proponer un gasto a cargo de una unidad |
| POST | `/api/v1/bk/gastos/{id}/accion` | `gastos:gestionar` | Aprobar, rechazar o pagar un gasto |
| GET | `/api/v1/bk/interbancarias` | `interbancarias:gestionar` | Operaciones interbancarias de mi entidad: pagadas por mis clientes y cobradas en mis comercios |
| GET | `/api/v1/bk/interbancarias/posicion` | `interbancarias:gestionar` | Posición neta de mi entidad frente a cada banco en el periodo |
| POST | `/api/v1/bk/nominas/periodos` | `nominas:generar` | Generar y pagar la nómina de un periodo |
| GET | `/api/v1/bk/organigrama` | `organigrama:leer` | Árbol del organigrama de una entidad institucional |
| POST | `/api/v1/bk/organigrama` | `organigrama:gestionar` | Cambiar el organigrama: unidad, puesto, nombrar, cesar, permiso o cerrar_unidad |
| GET | `/api/v1/bk/pasarela` | `pasarela:configurar` | Ver el producto pasarela de mi entidad |
| PUT | `/api/v1/bk/pasarela` | `pasarela:configurar` | Activar la pasarela y fijar sus parámetros |
| GET | `/api/v1/bk/presupuestos` | `presupuestos:leer` | Informe de una unidad: presupuesto, comprometido, pagado y disponible |
| PUT | `/api/v1/bk/presupuestos` | `presupuestos:gestionar` | Fijar el presupuesto anual de una unidad o el general de la entidad |
| POST | `/api/v1/bk/presupuestos/mensual` | `presupuestos:gestionar` | Fijar el presupuesto de un mes (reparto del anual) |
| POST | `/api/v1/bk/presupuestos/planes` | `presupuestos:gestionar` | Crear un plan plurianual (sobre de varios ejercicios) |
| POST | `/api/v1/bk/presupuestos/reasignaciones` | `presupuestos:gestionar` | Mover presupuesto entre dos unidades con la misma unidad superior |
| POST | `/api/v1/bk/recurrentes` | `recurrentes:gestionar` | Autorizar un pago recurrente de una unidad |
| POST | `/api/v1/bk/recurrentes/generar` | `recurrentes:gestionar` | Generar las propuestas de gasto de los pagos recurrentes de un periodo |
| POST | `/api/v1/bk/retribuciones` | `retribuciones:gestionar` | Fijar una retribución fija o un complemento autorizado |
| POST | `/api/v1/bk/solicitudes` | `solicitudes:gestionar` | Crear una solicitud de una unidad (prórroga, ampliación, reserva extra, financiación u otra) |
| POST | `/api/v1/bk/solicitudes/{id}/resolver` | `solicitudes:gestionar` | Resolver una solicitud: concedida o denegada |
| POST | `/api/v1/bk/tareas` | `tareas:gestionar` | Registrar una tarea que genera un complemento (para apps como NEXE) |
| POST | `/api/v1/bk/tareas/{id}/accion` | `tareas:gestionar` | Validar, pagar o rechazar una tarea |
| GET | `/api/v1/bk/tasas` | `tasas:gestionar` | Listar las tasas de mi entidad sobre sus pasarelas y comercios |
| POST | `/api/v1/bk/tasas` | `tasas:gestionar` | Crear una tasa sobre los pagos de la pasarela (para mis comercios, a mi beneficio) |
| POST | `/api/v1/bk/tasas/{id}/desactivar` | `tasas:gestionar` | Desactivar una tasa de mi entidad |
| GET | `/api/v1/bk/webhooks` | `webhooks:gestionar` | Listar los webhooks de mi entidad (sin secretos) |
| POST | `/api/v1/bk/webhooks` | `webhooks:gestionar` | Dar de alta un webhook. Devuelve el secreto una sola vez |
| GET | `/api/v1/bk/webhooks/entregas` | `webhooks:gestionar` | Eventos enviados a mi entidad: fecha, intentos y estado de entrega |
| DELETE | `/api/v1/bk/webhooks/{id}` | `webhooks:gestionar` | Dar de baja un webhook |
| POST | `/api/v1/bk/webhooks/{id}/rotar` | `webhooks:gestionar` | Rotar el secreto de un webhook. El anterior deja de valer |

### Diseños y tarjetas (5)

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| POST | `/api/v1/bk/tarjetas/cargos` | `tarjetas:cobrar` | Autorizar un cargo en una tarjeta de tu entidad |
| POST | `/api/v1/bk/tarjetas/cargos/{id}/liberar` | `tarjetas:cobrar` | Liberar un cargo autorizado que no se va a liquidar |
| POST | `/api/v1/bk/tarjetas/cargos/{id}/liquidar` | `tarjetas:cobrar` | Liquidar un cargo autorizado |
| GET | `/api/v1/bk/tarjetas/{ref}/nfc` | `tarjetas:gestionar` | Identificador y enlace NFC de una tarjeta |
| PUT | `/api/v1/bk/tarjetas/{ref}/nfc` | `tarjetas:gestionar` | Registrar o cambiar el identificador o enlace NFC de una tarjeta |

### Nómina y contratos (6)

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/v1/bk/empresas/{id}/complementos` | `nominas:read` | Catálogo de complementos de la entidad de la empresa |
| POST | `/api/v1/bk/empresas/{id}/complementos` | `retribuciones:gestionar` | Crear un complemento de actividad en el catálogo |
| POST | `/api/v1/bk/empresas/{id}/complementos/asignaciones` | `retribuciones:gestionar` | Asignar un complemento de actividad a un contrato |
| POST | `/api/v1/bk/empresas/{id}/complementos/asignaciones/{asig}/retirar` | `retribuciones:gestionar` | Retirar un complemento de un contrato a partir de una fecha |
| GET | `/api/v1/bk/empresas/{id}/nomina/conceptos` | `nominas:read` | Conceptos de nómina de un periodo, para emitir la nómina en NEXE |
| GET | `/api/v1/bk/empresas/{id}/nomina/recibos` | `nominas:read` | Recibos pagados de un periodo (salario y complementos), en JSON o PDF por persona |

### Nóminas y planes (2)

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/v1/bk/nominas` | `nominas:read` | Contratos de nómina de tu entidad (solo lectura) |
| GET | `/api/v1/bk/planes` | `planes:read` | Planes a plazos y suscripciones de tu entidad (solo lectura) |

### Pasarela de pago (11)

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/v1/bk/checkouts` | `checkout:crear` | Listar los pagos de mi cliente de API |
| POST | `/api/v1/bk/checkouts` | `checkout:crear` | Crear un pago en la pasarela |
| GET | `/api/v1/bk/checkouts/{id}` | `checkout:crear` | Estado de un pago |
| PUT | `/api/v1/bk/comercio/branding` | `branding:gestionar` | Fijar el nombre, logo y color de mi comercio en la ventana de pago |
| POST | `/api/v1/bk/comercio/logo` | `branding:gestionar` | Subir el logo de este comercio |
| GET | `/api/v1/bk/pagos` | `pagos:resolver` | Pagos pendientes de confirmación por mi banco |
| POST | `/api/v1/bk/pagos/canjear` | `pagos:resolver` | Canjear el código de pago de un cliente para ver el pago antes de aprobarlo |
| POST | `/api/v1/bk/pagos/{id}/resolucion` | `pagos:resolver` | Aprobar o rechazar un pago de mi cliente |
| GET | `/api/v1/bk/restricciones` | `pagos:restringir` | Ver las restricciones de pago del banco |
| PUT | `/api/v1/bk/restricciones` | `pagos:restringir` | Prohibir o permitir un medio, tipo de tarjeta, modalidad u operación de pago |
| POST | `/api/v1/bk/webhooks/entregas/{id}/reintentar` | `webhooks:gestionar` | Reintentar una entrega fallida |

### Subvenciones y reglas (22)

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/v1/bk/categorias` | `politicas:gestionar` | Categorías de comercio que asigna Placeta |
| GET | `/api/v1/bk/comercios` | `politicas:gestionar` | Directorio de comercios (cuentas de empresa activas) con su categoría |
| POST | `/api/v1/bk/convocatorias/{id}/reautorizacion` | `subvenciones:gestionar` | Decidir si lo recuperado de una deuda se vuelve a autorizar en la convocatoria |
| GET | `/api/v1/bk/empresas/{id}/convocatorias` | `subvenciones:gestionar` | Convocatorias de una empresa |
| POST | `/api/v1/bk/empresas/{id}/convocatorias` | `subvenciones:gestionar` | Abrir una convocatoria de subvención o bono |
| POST | `/api/v1/bk/empresas/{id}/convocatorias/{conv}/cerrar` | `subvenciones:gestionar` | Cerrar una convocatoria |
| POST | `/api/v1/bk/empresas/{id}/convocatorias/{conv}/concesiones` | `subvenciones:gestionar` | Conceder dentro de una convocatoria |
| GET | `/api/v1/bk/justificaciones` | `subvenciones:gestionar` | Justificaciones de gasto (todas o de una concesión) |
| POST | `/api/v1/bk/justificaciones` | `subvenciones:gestionar` | Justificar un gasto ya hecho por el beneficiario |
| POST | `/api/v1/bk/justificaciones/{id}/pagar` | `subvenciones:gestionar` | Aprobar y pagar una justificación (transfiere desde la cuenta de fondos) |
| POST | `/api/v1/bk/justificaciones/{id}/rechazar` | `subvenciones:gestionar` | Rechazar una justificación pendiente |
| GET | `/api/v1/bk/politicas` | `politicas:gestionar` | Reglas de uso de mi entidad (RBU y programas) |
| POST | `/api/v1/bk/politicas` | `politicas:gestionar` | Crear una regla de uso (sustituye a la activa del mismo ámbito) |
| POST | `/api/v1/bk/politicas/{id}/desactivar` | `politicas:gestionar` | Desactivar una regla de uso |
| GET | `/api/v1/bk/programas` | `subvenciones:gestionar` | Programas de subvención o bono de mi entidad |
| POST | `/api/v1/bk/programas` | `subvenciones:gestionar` | Crear un programa de subvención o bono |
| GET | `/api/v1/bk/programas/{id}/concesiones` | `subvenciones:gestionar` | Concesiones de un programa |
| POST | `/api/v1/bk/programas/{id}/concesiones` | `subvenciones:gestionar` | Conceder un importe máximo a un beneficiario dentro del programa |
| POST | `/api/v1/bk/subvenciones` | `subvenciones:gestionar` | Crear una subvención o bono (fondos autorizados) |
| GET | `/api/v1/bk/subvenciones/{id}/informe` | `subvenciones:gestionar` | Informe de justificación de una subvención |
| POST | `/api/v1/bk/subvenciones/{id}/revertir` | `subvenciones:gestionar` | Revertir un abono o toda la subvención |
| GET | `/api/v1/bk/tipos-destino` | `politicas:gestionar` | Tipos de cuenta de destino que existen en la plataforma |

### 11.2 Usuario (`/api/v1/me`): 38 operaciones

Autenticación: token de sesión `pus_…` en `Authorization: Bearer`. El permiso indicado debe estar concedido en la sesión.

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/v1/me` | `me:read` | Datos de la sesión: entidad y permisos |
| GET | `/api/v1/me/accounts` | `me:read` | Mis cuentas |
| POST | `/api/v1/me/accounts` | `me:contratar` | Abrir una cuenta personal propia (máximo 3 por entidad) |
| GET | `/api/v1/me/accounts/{iban}` | `me:read` | Ficha de una cuenta propia |
| GET | `/api/v1/me/accounts/{iban}/cards` | `me:read` | Tarjetas de una cuenta propia (sin número completo) |
| GET | `/api/v1/me/accounts/{iban}/receipts` | `me:read` | Recibos fiscales de una cuenta propia |
| GET | `/api/v1/me/accounts/{iban}/statement` | `me:read` | Extracto del periodo: saldo inicial, movimientos y saldo final |
| GET | `/api/v1/me/accounts/{iban}/transactions` | `me:read` | Movimientos (paginados por cursor) |
| GET | `/api/v1/me/beneficiaries` | `me:read` | Beneficiarios guardados |
| POST | `/api/v1/me/beneficiaries` | `me:transfer` | Guardar un beneficiario |
| DELETE | `/api/v1/me/beneficiaries/{id}` | `me:transfer` | Borrar un beneficiario |
| POST | `/api/v1/me/cards/{ref}` | `me:seguridad` | Suspender o reactivar una tarjeta propia |
| POST | `/api/v1/me/cards/{ref}/diseno` | `me:seguridad` | Aplicar a una tarjeta un diseño comprado por su cuenta |
| GET | `/api/v1/me/designs` | `me:read` | Diseños disponibles para ti en tu entidad |
| GET | `/api/v1/me/designs/comprados` | `me:read` | Diseños que has comprado |
| POST | `/api/v1/me/designs/{codigo}/buy` | `me:transfer` | Comprar un diseño desde una cuenta propia |
| GET | `/api/v1/me/deudas` | `me:read` | Mis deudas en las cuentas a las que tengo acceso |
| POST | `/api/v1/me/deudas/{id}/disputa` | `me:disputas` | Reclamar sobre una deuda pagada |
| POST | `/api/v1/me/deudas/{id}/pagar` | `me:transfer` | Pagar una deuda (parcial o total) |
| GET | `/api/v1/me/disputas` | `me:read` | Mis reclamaciones sobre deudas |
| GET | `/api/v1/me/exportar` | `me:read` | Exportar mis datos (acceso y portabilidad) |
| GET | `/api/v1/me/lookup` | `me:read` | Comprobar un IBAN antes de transferir |
| GET | `/api/v1/me/notifications` | `me:read` | Notificaciones (ingresos y cargos) |
| POST | `/api/v1/me/notifications/read` | `me:read` | Marcar notificaciones como leídas |
| GET | `/api/v1/me/plans` | `me:read` | Mis planes a plazos y suscripciones |
| GET | `/api/v1/me/previsiones` | `me:read` | Mis próximos movimientos (máximo 366 días) |
| GET | `/api/v1/me/rbu` | `me:read` | Mis bonos de la RBU |
| GET | `/api/v1/me/rbu/saldo` | `me:read` | Saldo RBU de mi tarjeta prepago, por asignación y caducidad |
| POST | `/api/v1/me/rbu/{id}/claim` | `me:transfer` | Reclamar un bono de la RBU |
| GET | `/api/v1/me/receipts/{ref}/certificate` | `me:read` | Certificado de cálculo de un recibo propio |
| GET | `/api/v1/me/requests` | `me:contratar` | Mis solicitudes (préstamo o cuenta) |
| POST | `/api/v1/me/requests` | `me:contratar` | Solicitar un préstamo o una cuenta (queda pendiente) |
| DELETE | `/api/v1/me/sessions` | `me:seguridad` | Cerrar todas mis sesiones excepto la actual |
| GET | `/api/v1/me/sessions` | `me:read` | Mis sesiones abiertas (sin tokens) |
| POST | `/api/v1/me/transfers` | `me:transfer` | Transferir dinero desde una cuenta propia |
| GET | `/api/v1/me/transfers/scheduled` | `me:read` | Transferencias programadas activas |
| POST | `/api/v1/me/transfers/scheduled` | `me:transfer` | Programar una transferencia (única o periódica) |
| DELETE | `/api/v1/me/transfers/scheduled/{id}` | `me:transfer` | Cancelar una transferencia programada |

### 11.3 Otras rutas públicas: 15 operaciones

| Método | Ruta | Permiso | Qué hace |
|---|---|---|---|
| GET | `/api/checkout/{token}` | `—` | Estado público de un pago (ventana de pago) |
| POST | `/api/checkout/{token}/cancelar` | `—` | Cancelar un pago pendiente |
| POST | `/api/v1/accounts` | `accounts:write` | Crear una cuenta |
| GET | `/api/v1/accounts/{iban}` | `accounts:read` | Ficha de una cuenta de la entidad |
| GET | `/api/v1/accounts/{iban}/cards` | `cards:read` | Tarjetas de una cuenta |
| GET | `/api/v1/accounts/{iban}/membership` | `memberships:read` | Estado de la membresía |
| POST | `/api/v1/accounts/{iban}/membership/renew` | `memberships:write` | Renovar la membresía |
| GET | `/api/v1/accounts/{iban}/receipts` | `accounts:read` | Recibos de una cuenta de la entidad |
| GET | `/api/v1/accounts/{iban}/transactions` | `accounts:read` | Movimientos de una cuenta de la entidad |
| GET | `/api/v1/designs` | `products:read` | Catálogo de diseños para tu entidad |
| GET | `/api/v1/products` | `products:read` | Productos de la entidad |
| DELETE | `/api/v1/sessions` | `me:read` | Cerrar la sesión actual |
| POST | `/api/v1/sessions` | `sesiones:crear` | Crear sesión de usuario (firmada) |
| POST | `/api/v1/transfers` | `transfers:write` | Transferencia entre cuentas de la entidad |
| GET | `/api/v1/transfers/{ref}` | `transfers:read` | Estado de una transferencia |

---

## 12. Riesgos y limitaciones (léelo antes de publicar)

Esta sección describe lo que **hace hoy el código**, aunque no coincida con lo que se prometía en otros documentos.

1. **Las rutas de banca no exigen firma.** Solo `/api/v1/sessions` exige la firma HMAC. El resto de rutas de banca comprueba solo la **clave** y el **permiso**. Una clave `plk_…` filtrada permite usar las rutas de banca que tenga concedidas, aunque no tenga el secreto de firma. **Mitigación inmediata:** trata la clave como secreto de máxima sensibilidad, concede solo los permisos necesarios y rótala ante cualquier sospecha. **Mejora propuesta (pendiente de aprobación):** exigir firma en todas las rutas de banca, como ya hace la creación de sesiones.
2. **La documentación previa dice otra cosa.** `docs/API_BANCOS.md` afirma que «cada petición de servidor va firmada». Eso no es cierto para las rutas de banca distintas de la creación de sesiones. Hasta que se corrija, guíate por este documento.
3. **No hay renovación de sesión desde el usuario.** Cuando el token caduca, tu servidor debe crear otra sesión. La propuesta de renovación está documentada, pero no implementada.
4. **Recibos de nómina sencillos.** Son PDF de texto, sin logotipo ni formato legal.
5. **Lista de eventos de webhook.** La definitiva la confirma la base de datos del proyecto; no uses eventos que no estén en la lista sin confirmarlos.
6. **Producción.** Nada de esta API se ha probado todavía en la base de datos de producción.

---

## 13. Lista de comprobación antes de salir a producción

- [ ] Clave y secreto de firma guardados solo en el servidor, con gestor de secretos.
- [ ] Permisos mínimos concedidos a tu clave (ninguno de más).
- [ ] Todas las llamadas de sesión firmadas, con nonce único y marca de tiempo actual.
- [ ] Sesiones creadas solo tras autenticar al usuario, y tokens en memoria (nunca en `localStorage`).
- [ ] Clave de idempotencia generada por operación y reutilizada en los reintentos.
- [ ] Webhooks en **https**, firma verificada sobre el cuerpo crudo, proceso idempotente.
- [ ] Manejo de `401`, `403`, `422`, `429` y `5xx` según la sección 7.
- [ ] Límite de peticiones respetado, con caché para lecturas repetidas.
- [ ] Pruebas completas en el entorno de pruebas, incluida la reversión de un error.
- [ ] Plan para rotar claves y secretos, y procedimiento ante una filtración.
- [ ] Registro de peticiones con identificadores, sin secretos ni tokens en los logs.

---

_Este documento es guía de implementación. Las rutas, parámetros y ejemplos exactos están en `docs/openapi.json`. Si hay contradicción, prevalece el contrato, y conviene avisar para corregir este documento._
