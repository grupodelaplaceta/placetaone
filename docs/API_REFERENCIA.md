# Referencia de la API de Placeta One para entidades bancarias

Esta referencia describe todos los endpoints que necesita una aplicación o web de banca online. Cada entidad construye su propia web o app; Placeta One aporta los datos, las operaciones y las comprobaciones de seguridad.

- **Base URL:** `https://<tu-entorno>` (producción y pruebas tienen dominios distintos).
- **Formato:** JSON en peticiones y respuestas (`content-type: application/json`).
- **Versión:** `/api/v1`. Un cambio incompatible se publicaría como `/api/v2`.
- **Guía de seguridad y ejemplos de integración:** `API_BANCOS.md`.

## 1. Autenticación

Hay tres tipos de credencial. Cada uno se usa en un sitio distinto.

| Credencial | Dónde vive | Quién la usa | Para qué |
|---|---|---|---|
| **Clave de servidor** `plk_…` | Solo backend del banco | Servidor del banco | Llamadas de servidor a servidor |
| **Secreto de firma** | Solo backend del banco | Servidor del banco | Firmar la creación de sesiones |
| **Token de sesión** `pus_…` | Navegador o app del usuario | Usuario final | Todas las operaciones del usuario |

Reglas que el servidor aplica siempre:

- Las claves de servidor **se rechazan con 403** si la petición trae cabeceras de navegador (`Origin`, `Sec-Fetch-Site`). No se pueden usar desde una web.
- El token de sesión **dura 15 minutos por defecto** (máximo 60) y se puede revocar con `DELETE /api/v1/sessions`.
- El usuario **nunca se indica en la petición**: sale del token. No existe ningún parámetro «usuario» en los endpoints de usuario.

### Firma de la creación de sesiones

Cada llamada a `POST /api/v1/sessions` y `POST /api/v1/bk/*` de creación lleva estas cabeceras:

| Cabecera | Valor |
|---|---|
| `x-api-key` | Tu clave `plk_…` |
| `x-timestamp` | Marca de tiempo en milisegundos (ventana de ±5 minutos) |
| `x-nonce` | Cadena aleatoria de 16 a 64 caracteres. Cada petición lleva uno nuevo |
| `x-signature` | HMAC-SHA256 en hexadecimal de `"<timestamp>.<cuerpo>"` con tu secreto de firma |

Un nonce repetido responde **409**. Una firma incorrecta o una marca de tiempo fuera de ventana, **401**.

## 2. Formatos comunes

- **Importes:** número en Pz con dos decimales (`120.5`). Siempre positivos en las peticiones.
- **Fechas:** ISO 8601 en UTC (`2026-11-03T09:00:00Z`). Las fechas sin hora son `AAAA-MM-DD`.
- **Identificadores:** las cuentas se identifican por su **IBAN** (`PZ-EEEE-CCCC`). Los movimientos y los bonos tienen un identificador numérico o UUID.
- **Identificador de persona:** el **DIP**. Se normaliza quitando espacios y guiones y pasando a mayúsculas. Formato aceptado: de 5 a 20 letras y números.
- **Paginación:** los movimientos usan **cursor**. La respuesta trae `siguiente`; se pasa como `?antes=<siguiente>` para la página siguiente. Máximo 100 por página.
- **Idempotencia:** las operaciones que mueven dinero o crean algo exigen la cabecera `Idempotency-Key` (máximo 128 caracteres). Repetir la misma clave devuelve el resultado original y **no duplica** la operación.
- **Límites de peticiones:** por cliente. Al superarlos, **429**.
- **CORS:** solo para los orígenes que el personal de Placeta registra para tu cliente. Cualquier otro origen no recibe cabeceras CORS.

## 3. Errores

Toda respuesta de error tiene la forma:

```json
{ "error": "Mensaje legible y seguro para mostrar" }
```

| Código | Significado | Qué hacer |
|---|---|---|
| 400 | Datos mal formados o fuera de rango | Corrige la petición |
| 401 | Sesión o firma no válida, caducada o revocada | Pide una sesión nueva a tu backend |
| 403 | Permiso insuficiente, o clave usada desde un navegador | Revisa los permisos del cliente |
| 404 | No encontrado **o no es tuyo** (no se distingue, a propósito) | Muestra «no encontrado» |
| 409 | Petición repetida (nonce) | Genera un nonce nuevo y reintenta |
| 422 | Operación no posible (fondos insuficientes, cuenta destino no válida, etc.) | Muestra el mensaje al usuario |
| 429 | Demasiadas peticiones | Reintenta más tarde con espera exponencial |
| 500 | Error interno | Reintenta; si persiste, avisa a Placeta |

## 4. Permisos

| Permiso | Tipo | Concede |
|---|---|---|
| `sesiones:crear` | Servidor | Crear y revocar sesiones de usuario |
| `usuarios:gestionar` | Servidor | Vincular usuarios (por DIP) a cuentas de tu entidad |
| `personas:buscar` | Servidor | Buscar por DIP las cuentas de tu entidad |
| `accounts:read` / `accounts:write` | Servidor | Consultar y crear cuentas de tu entidad (operaciones de back office) |
| `cards:read` | Servidor | Consultar tarjetas de una cuenta |
| `memberships:read` / `memberships:write` | Servidor | Consultar y renovar membresías |
| `transfers:read` / `transfers:write` | Servidor | Consultar y ordenar transferencias de cualquier cuenta de tu entidad |
| `products:read` | Servidor | Consultar los productos de la entidad |
| `origenes:gestionar` | Servidor | Solicitar, listar y retirar los orígenes de navegador (CORS) de tu cliente |
| `me:read` | Usuario | Leer los datos del propio usuario |
| `me:transfer` | Usuario | Ordenar transferencias, programarlas y reclamar la RBU |
| `me:contratar` | Usuario | Abrir cuentas propias y solicitar préstamos o cuentas |
| `me:seguridad` | Usuario | Suspender tarjetas propias y cerrar sesiones |

**Importante:** `accounts:read`, `transfers:write` y similares permiten operar sobre **toda la entidad**. Son de servidor y **no deben entregarse nunca a una web o app** ni incluirse en el token del usuario. Para una app de usuario, los permisos que corresponden son `me:read` y `me:transfer`.

---

## 5. Endpoints de servidor del banco

### 5.1 Vincular un usuario a una cuenta
`POST /api/v1/bk/link-account` · permiso `usuarios:gestionar`

Da de alta a una persona (por su DIP) como titular o cotitular de una cuenta de **tu** entidad.

Cuerpo:
```json
{ "dip": "12345678Z", "iban": "PZ-0001-0002", "rol": "holder" }
```
`rol`: `holder` (titular), `coholder` (cotitular) o `authorized` (autorizado, solo lectura). Por defecto, `holder`.

Respuesta `201`:
```json
{ "vinculado": true }
```
Errores: `404` si la cuenta no es de tu entidad; `400` si el DIP no es válido.

### 5.2 Buscar a una persona por DIP
`GET /api/v1/bk/personas?dip=12345678Z` · permiso `personas:buscar`

Devuelve las cuentas que esa persona tiene **en tu entidad**. La respuesta es idéntica si el DIP no existe y si no tiene cuentas en tu banco: no se puede usar para saber en qué otros bancos está una persona.

Respuesta `200`:
```json
{
  "cuentas": [
    { "iban": "PZ-0001-0002", "nombre": "Cuenta corriente", "tipo": "personal", "rol": "holder", "estado": "active" }
  ]
}
```
Cada búsqueda queda registrada en auditoría con un **hash** del DIP, nunca con el DIP en claro.

### 5.3 Crear una sesión de usuario
`POST /api/v1/sessions` · permiso `sesiones:crear` · firmada (ver sección 1)

Cuerpo:
```json
{ "dip": "12345678Z", "minutos": 15, "permisos": ["me:read", "me:transfer"] }
```
`minutos`: entre 1 y 60 (por defecto 15). `permisos`: subconjunto de `me:read` y `me:transfer`; nunca más de lo que tiene el cliente.

Respuesta `201`:
```json
{ "token": "pus_…", "expira": "2026-11-03T09:15:00.000Z", "permisos": ["me:read", "me:transfer"] }
```

Llama a este endpoint **solo después** de autenticar a la persona en tu propio sistema.

### 5.4 Revocar una sesión
`DELETE /api/v1/sessions` · cabecera `authorization: Bearer pus_…`

Revoca el token de la sesión actual. Respuesta `200`: `{ "revocada": true }`.

### 5.5 Endpoints de back office (servidor)

Estos endpoints usan las claves de servidor con permisos amplios. Son para sistemas internos del banco; **nunca para su web o app**.

| Método y ruta | Permiso | Qué hace |
|---|---|---|
| `GET /api/v1/accounts/{iban}` | `accounts:read` | Ficha de una cuenta de tu entidad |
| `POST /api/v1/accounts` | `accounts:write` | Crear una cuenta. Cuerpo: `name`, `owner`, `product_id` |
| `GET /api/v1/accounts/{iban}/transactions` | `accounts:read` | Movimientos de cualquier cuenta de tu entidad |
| `GET /api/v1/accounts/{iban}/receipts` | `accounts:read` | Recibos de cualquier cuenta de tu entidad |
| `GET /api/v1/accounts/{iban}/cards` | `cards:read` | Tarjetas de una cuenta |
| `GET /api/v1/accounts/{iban}/membership` | `memberships:read` | Estado de la membresía |
| `POST /api/v1/accounts/{iban}/membership/renew` | `memberships:write` | Renovar la membresía. Cuerpo: `user_id` |
| `POST /api/v1/transfers` | `transfers:write` | Transferencia entre cuentas de tu entidad. Cuerpo: `from_iban`, `to_iban`, `amount`, `memo`, `user_id`. Requiere `Idempotency-Key`. Respuesta: `{ "transfer", "operation" }` |
| `GET /api/v1/transfers/{ref}` | `transfers:read` | Estado de una transferencia |
| `GET /api/v1/products` | `products:read` | Productos de la entidad |

---

## 6. Endpoints de usuario (web y app)

Todos llevan `authorization: Bearer pus_…` y responden solo con datos del usuario de la sesión.

### 6.1 Datos de la sesión
`GET /api/v1/me` · `me:read`

```json
{ "banco": { "codigo": "0001", "nombre": "Mi Banco" }, "permisos": ["me:read", "me:transfer"] }
```

### 6.2 Mis cuentas
`GET /api/v1/me/accounts` · `me:read`

Devuelve solo las cuentas del usuario en su entidad.
```json
{
  "cuentas": [
    { "iban": "PZ-0001-0002", "nombre": "Cuenta corriente", "tipo": "personal", "rol": "holder", "saldo": 1520.4, "disponible": 1500.4 }
  ]
}
```

### 6.3 Ficha de una cuenta
`GET /api/v1/me/accounts/{iban}` · `me:read`

```json
{
  "iban": "PZ-0001-0002", "nombre": "Cuenta corriente", "tipo": "personal", "estado": "active", "rol": "holder",
  "saldo": 1520.4, "reservado": 20, "disponible": 1500.4, "limite_diario": 3000, "descubierto": false
}
```
Una cuenta que no es del usuario responde `404`.

### 6.4 Movimientos de una cuenta
`GET /api/v1/me/accounts/{iban}/transactions?antes=<cursor>&limite=50` · `me:read`

```json
{
  "movimientos": [
    { "id": 9120, "fecha": "2026-10-29T10:12:00Z", "sentido": "debit", "importe": 80, "tipo": "transfer", "memo": "Cena" }
  ],
  "siguiente": 9070
}
```
`sentido`: `debit` (sale) o `credit` (entra). `siguiente` es `null` cuando no hay más páginas.

### 6.5 Recibos de una cuenta
`GET /api/v1/me/accounts/{iban}/receipts` · `me:read`

```json
{
  "recibos": [
    { "ref": "REC-2026-000123", "impuesto": "IVA", "base": 1000, "importe": 120, "pagado": 0,
      "estado": "issued", "vence": "2026-11-15", "creado": "2026-10-29T08:00:00Z" }
  ]
}
```

### 6.6 Certificado de un recibo
`GET /api/v1/me/receipts/{ref}/certificate` · `me:read`

Acredita cómo se calculó el importe: norma usada, base, desglose por tramos, huella de la norma y cadena de huellas. Un recibo que se haya modificado tiene varios certificados; este devuelve el **vigente** y cuántos tiene en `certificados_del_recibo`.

```json
{
  "recibo": "REC-2026-000123", "norma": "IVA", "version": 1, "huella_norma": "9f2c…",
  "base": 1000, "importe": 120, "calculo": { "tramos": [] }, "tipo": "recibo",
  "seq": 4821, "hash": "a7e1…", "hash_anterior": "3b0c…", "reemplaza": null,
  "emitido": "2026-10-29T08:00:00Z", "certificados_del_recibo": 1
}
```
Un recibo ajeno responde `404`.

### 6.7 Comprobar un IBAN antes de transferir
`GET /api/v1/me/lookup?iban=PZ-0001-0002` · `me:read`

```json
{ "existe": true, "entidad": "0001", "titular": "Ma***" }
```
Si el IBAN no existe o no está activo: `{ "existe": false }`. Muestra el titular abreviado para que el usuario confirme el destinatario antes de pagar.

### 6.8 Transferir dinero
`POST /api/v1/me/transfers` · `me:transfer` · requiere `Idempotency-Key`

Cuerpo:
```json
{ "desde_iban": "PZ-0001-0002", "hacia_iban": "PZ-0001-0009", "importe": 50, "concepto": "Cena" }
```
Respuesta `201`: `{ "transaccion": "…" }`.

Errores: `422` si la cuenta de origen no es del usuario (o no tiene permiso de escritura, por ejemplo un autorizado), si el destino no existe o si no hay fondos.

### 6.9 Transferencias programadas
`GET /api/v1/me/transfers/scheduled` · `me:read`

```json
{
  "programadas": [
    { "id": "…", "origen": "PZ-0001-0002", "destino": "PZ-0001-0009", "importe": 200,
      "proxima": "2026-11-01T09:00:00Z", "periodicidad": "30 days", "estado": "active", "concepto": "Alquiler" }
  ]
}
```

`POST /api/v1/me/transfers/scheduled` · `me:transfer` · requiere `Idempotency-Key`
```json
{ "desde_iban": "PZ-0001-0002", "hacia_iban": "PZ-0001-0009", "importe": 200,
  "fecha": "2026-11-01T09:00:00Z", "periodicidad_dias": 30, "concepto": "Alquiler" }
```
`periodicidad_dias`: `0` o ausente para una sola vez; de 1 a 366 para repetir. Mínimo un día. Respuesta `201`: `{ "programada": "…" }`.

`DELETE /api/v1/me/transfers/scheduled/{id}` · `me:transfer` → `{ "cancelada": true }`.

### 6.10 Previsión de mis movimientos
`GET /api/v1/me/previsiones?desde=2026-10-29&hasta=2026-11-30` · `me:read`

Próximos impuestos, cuotas, cargos de suscripción, nóminas, programadas, deudas y caducidades de RBU de **sus cuentas**. Máximo 366 días.
```json
{
  "desde": "2026-10-29", "hasta": "2026-11-30",
  "previsiones": [
    { "fecha": "2026-11-01", "tipo": "Transferencia programada", "referencia": "Alquiler",
      "iban": "PZ-0001-0002", "importe": 200, "estado": "cobrable", "detalle": "Recurrente" }
  ]
}
```
`estado`: `cobrable` (la cuenta tiene fondos), `sin fondos`, `vencido`, `programado`, `estimado`.

### 6.11 RBU
`GET /api/v1/me/rbu` · `me:read` → `{ "bonos": [ { "id", "semana", "importe", "estado", "caduca", "cartera" } ] }`

`POST /api/v1/me/rbu/{id}/claim` · `me:transfer` · requiere `Idempotency-Key`. Reclama el bono; el importe pasa de la cuenta de origen de la RBU a la cartera del usuario. Respuesta `201`: `{ "transaccion": "…" }`. Un bono no reclamado a tiempo **caduca**.

### 6.12 Planes a plazos y suscripciones
`GET /api/v1/me/plans` · `me:read`

```json
{
  "planes": [
    { "id": "…", "tipo": "installment", "cuenta": "PZ-0001-0002", "capital": 12000, "tasa_anual": 12,
      "cuotas": 12, "estado": "active", "proxima": "2026-11-15" }
  ]
}
```

### 6.13 Cerrar sesión
`DELETE /api/v1/sessions` (ver 5.4).

---

## 7. Flujos completos de una app bancaria

### 7.1 Entrar y ver el inicio
1. El usuario se autentica en **tu** sistema.
2. Tu backend crea la sesión (5.3) y devuelve el token a la app.
3. La app pide `GET /api/v1/me/accounts`, `GET /api/v1/me/previsiones` y `GET /api/v1/me/rbu`.

### 7.2 Pagar a alguien
1. `GET /api/v1/me/lookup?iban=…` → muestra el titular abreviado y pide confirmación.
2. `POST /api/v1/me/transfers` con `Idempotency-Key` nueva por intento.
3. Si la respuesta es `422`, muestra el mensaje; si es un error de red, reintenta **con la misma** `Idempotency-Key`.

### 7.3 Programar un pago mensual
1. `POST /api/v1/me/transfers/scheduled` con `periodicidad_dias: 30`.
2. `GET /api/v1/me/transfers/scheduled` para verla; `DELETE …/{id}` para cancelarla.

### 7.4 Revisar un recibo
1. `GET /api/v1/me/accounts/{iban}/receipts` → lista.
2. `GET /api/v1/me/receipts/{ref}/certificate` → muestra cómo se calculó.

### 7.5 Cerrar la sesión al salir
`DELETE /api/v1/sessions` y borra el token de memoria.

## 8. Lo que aún no está en esta versión

- **Segundo factor (MFA) del usuario:** necesita un proveedor de SMS o de códigos TOTP y su almacenamiento seguro. Hoy la protección es el token corto y la entidad que autentica a su usuario.
- **Aprobación de préstamos en línea:** las solicitudes quedan pendientes. La resolución la hace el personal del banco; no hay aprobación automática.
- **Notificaciones push:** la API entrega la bandeja de notificaciones. El envío al móvil lo hace la app del banco con su propio servicio de push.
- **Extractos en PDF:** el extracto se entrega en JSON. El PDF se genera en el cliente a partir de él.
- **Tarjetas:** el usuario puede consultarlas y suspenderlas o reactivarlas. El alta, el bloqueo y el cierre los gestiona el banco.

## 9. Pruebas

El script `scripts/aislamiento.mjs` comprueba el aislamiento entre dos usuarios de una entidad. Ejecútalo en tu entorno de pruebas antes de publicar.

## 10. Novedades de la versión 1.1

La especificación completa en formato OpenAPI está en `openapi.json`. Esta sección describe lo nuevo.

### 10.1 Ficha, extracto y apertura de cuentas
- `GET /api/v1/me/accounts/{iban}` · `me:read` → saldo, reservado, disponible, límite diario y descubierto.
- `GET /api/v1/me/accounts/{iban}/statement?desde=&hasta=` · `me:read` → saldo inicial, movimientos del periodo y saldo final. Máximo 366 días.
- `POST /api/v1/me/accounts` · `me:contratar` · `Idempotency-Key` → abre una cuenta personal propia (máximo 3 por entidad). Body: `{ "nombre": "…" }`.

### 10.2 Beneficiarios
- `GET /api/v1/me/beneficiaries` · `me:read`
- `POST /api/v1/me/beneficiaries` · `me:transfer` → body `{ "alias", "iban" }`. El IBAN debe existir y estar activo.
- `DELETE /api/v1/me/beneficiaries/{id}` · `me:transfer`

### 10.3 Tarjetas
- `GET /api/v1/me/accounts/{iban}/cards` · `me:read` → referencia, tipo, últimos 4 dígitos, caducidad, estado y límite. Nunca el número completo.
- `POST /api/v1/me/cards/{ref}` · `me:seguridad` → body `{ "estado": "suspended" | "active" }`. Solo suspende o reactiva; el bloqueo y el cierre los hace el banco.

### 10.4 Notificaciones
- `GET /api/v1/me/notifications?solo_nuevas=1&limite=50` · `me:read` → ingresos y cargos de sus cuentas, generados automáticamente con cada movimiento.
- `POST /api/v1/me/notifications/read` · `me:read` → body `{ "ids": [..] }`. Sin `ids`, marca todas.

### 10.5 Solicitudes
- `GET /api/v1/me/requests` · `me:contratar`
- `POST /api/v1/me/requests` · `me:contratar` · `Idempotency-Key` → body `{ "tipo": "prestamo" | "cuenta", "importe", "cuotas", "motivo" }`. Préstamos entre 0 y 50.000 Pz, de 1 a 120 cuotas. Quedan pendientes.

### 10.6 Sesiones
- `GET /api/v1/me/sessions` · `me:read` → sesiones abiertas, sin tokens.
- `DELETE /api/v1/me/sessions` · `me:seguridad` → cierra todas las demás (útil tras cambiar la contraseña).

### 10.7 Búsqueda por DIP (servidor)
- `GET /api/v1/bk/personas?dip=` · `personas:buscar` → cuentas de la persona **en su entidad**. Responde igual si el DIP no existe que si no tiene cuentas allí. Cada búsqueda se registra con un hash del DIP.

### 10.8 Permisos de la sesión
Un cliente puede conceder al usuario: `me:read`, `me:transfer`, `me:contratar` y `me:seguridad`. Nunca más de los que tiene el propio cliente.

### 10.9 Orígenes de navegador (CORS) · `origenes:gestionar`

Para que tu web pueda llamar a la API desde el navegador, su dirección debe estar **aprobada** para tu cliente.

- `GET /api/v1/bk/origenes` → lista tus orígenes con su estado (`pendiente`, `aprobado`, `rechazado`).
- `POST /api/v1/bk/origenes` → body `{ "origen": "https://app.tubanco.es" }`. Queda **pendiente** hasta que Placeta lo apruebe.
- `DELETE /api/v1/bk/origenes?origen=https://app.tubanco.es` → lo retira de inmediato.

Reglas:

- Formato: `https://dominio` con puerto opcional. Sin ruta (`/algo`), sin comodines (`*`), sin mayúsculas (se normalizan).
- Máximo 10 orígenes por cliente.
- Un origen aprobado vale **solo para tu cliente**. Otro cliente de la plataforma no puede usarlo para llamar a la API en tu nombre.
- `http://localhost` y dominios de prueba solo se aceptan con `entorno: "pruebas"`, y únicamente en un entorno de pruebas.
- CORS no protege nada por sí solo: la protección real son el token de sesión y las comprobaciones de cuenta. CORS decide qué páginas pueden leer las respuestas en el navegador.
- CORS solo cubre el **origen**. No puede restringir una ruta concreta dentro de tu web.
