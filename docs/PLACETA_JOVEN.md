# Placeta Joven: cuenta joven, compras con IVA y API

> Módulo nuevo (migración 0067). **No ejecutado en PostgreSQL**: pruébalo en la base de pruebas antes de usar dinero real.

## 1. Qué es

Una **cuenta Placeta Joven** es una cuenta a nombre de una persona (su DIP), que solo sirve para la plataforma Placeta Joven. Está **capada**:

- **Solo recibe dinero** de cuentas Joven, de **administración** (cuentas de tipo `system` de la entidad) o de otras cuentas Joven.
- **Solo gasta** en cuentas Joven, en cuentas de administración o en **comercios Joven**.
- **Nunca** envía dinero a empresas que no sean comercios Joven, ni a cuentas personales ni a otras cuentas de usuario.

Esta regla no depende de la API ni del portal: la **base de datos** la comprueba en cada transacción antes de confirmarla. Si una operación la incumple, se revierte entera.

## 2. Diferencia con la cuenta junior

Ya existe una cuenta `junior` (con tutor legal y membresías). Placeta Joven es un tipo **distinto** (`joven`), con reglas de gasto propias. Decidir si se fusionan es pendiente. Hasta entonces, no mezcles ambos tipos en el mismo flujo.

## 3. Puesta en marcha

1. **Permiso.** La Junta concede a tu clave el permiso `joven:gestionar`.
2. **Comercios.** La Junta marca como comercios Joven las empresas que aceptan la cuenta: `POST /api/admin/joven/comercios` con `{ "iban", "activo": true }`. Solo cuentas de empresa pueden serlo.
3. **Cuenta recaudadora del IVA.** Debe existir la regla fiscal `IVA` con su cuenta recaudadora (tipo `system`). Sin ella, las compras fallan con «No hay cuenta recaudadora de IVA configurada».
4. **IVA.** El ajuste `joven_iva_pct` (por defecto **12 %**) está en Configuración → Placeta Joven. Como es sensible, cambiarlo exige doble firma.

## 4. Crear y consultar la cuenta

| Qué | Cómo |
|---|---|
| Crear la cuenta de una persona | `POST /api/v1/bk/joven/cuentas` con `{ "dip" }`. Si ya existe, responde 200 con la existente |
| Saber la cuenta de una persona (para el portal) | `GET /api/v1/bk/joven/cuentas?dip=…` → `{ iban, disponible }` |

El portal usa el segundo para **preseleccionar la cuenta Joven** en cada compra, sin pedir nada al usuario.

## 5. Comprar

`POST /api/v1/bk/joven/pagos` con cabecera `Idempotency-Key` (8 a 80 caracteres) y:

```json
{ "dip": "23749931M", "comercio_iban": "PZ-0000-0400", "importe": 25, "concepto": "Compra cuaderno" }
```

- Si no envías `joven_iban`, la plataforma usa la cuenta Joven del `dip`.
- **El importe incluye el IVA.** El sistema calcula la base: `base = importe / (1 + IVA%)`, redondeada a céntimos, y el IVA es la diferencia. Con 25 Pz y 12 %: base 22,32 Pz, IVA 2,68 Pz.
- La **base** va al comercio y el **IVA** a la cuenta recaudadora. Son dos transferencias dentro de una misma operación: o salen las dos, o no sale ninguna.
- Si repites la petición con la misma clave, **no se cobra otra vez**: devuelve el pago original (200).

Respuesta (201): `{ "base": 22.32, "iva": 2.68, "iva_pct": 12, "total": 25, "repetida": false }`.

## 6. Recargar

`POST /api/v1/bk/joven/recargas` con `Idempotency-Key`, `origen_iban` (cuenta **de administración**) y `joven_iban` o `dip`. La recarga no lleva IVA. Cualquier otro origen se rechaza.

## 7. Ver movimientos

`GET /api/v1/bk/joven/cuentas/{iban}/movimientos?desde=AAAA-MM-DD&hasta=AAAA-MM-DD&limite=50`

Cada movimiento trae: `fecha`, `tipo` (`entrada` o `salida`), `importe`, `concepto`, `estado`, `contraparte` (tipo y nombre; las cuentas Joven se muestran como «Placeta Joven») y, en las compras, `desglose` con base, IVA y porcentaje.

Por defecto muestra los últimos 30 días.

## 8. Comercios

`GET /api/v1/bk/joven/comercios` lista los comercios Joven de tu entidad. Son los únicos destinos válidos para una compra.

## 9. Errores que puedes encontrar

| Mensaje | Qué significa |
|---|---|
| «Placeta Joven: el dinero solo puede moverse entre cuentas Joven, administración o comercios Joven» | Un intento de enviar o recibir dinero de una cuenta no permitida |
| «Comercio Placeta Joven no válido» | El destino no es un comercio Joven activo |
| «Cuenta Placeta Joven no encontrada en tu entidad» | El IBAN no es una cuenta Joven de tu entidad |
| «Clave de idempotencia de 8 a 80 caracteres» | Falta o es corta la cabecera `Idempotency-Key` |
| «No hay cuenta recaudadora de IVA configurada» | Falta la regla fiscal `IVA` con su cuenta |
| «La recarga solo puede salir de una cuenta de administración de tu entidad» | El origen de la recarga no es de tipo `system` |

## 10. Límites conocidos (léelos antes de publicar)

- **No verificado en PostgreSQL.** La regla de circulación depende de un disparador diferido; hay que probar en la base de pruebas que una transferencia prohibida falla.
- **Cuentas de administración.** Son todas las de tipo `system` (incluidas comisiones y liquidación). Si quieres limitarlo a unas pocas, hay que concretarlo.
- **Sin tutor ni verificación de edad.** La cuenta no pide tutor legal ni comprueba la edad. Para menores de edad, esto debe decidirse antes de lanzar.
- **Sin tarjeta.** No hay tarjeta física ni prepago para Placeta Joven: solo compras por API.
- **Sin acceso directo del usuario.** Las rutas `/api/v1/me/...` son de cuentas personales. Placeta Joven se opera desde la plataforma (cliente de banca).
- **Devoluciones.** La reversión de una compra es posible (el sistema la permite entre cuentas del mismo tipo), pero el desglose de IVA queda registrado tal cual.
- **Un IVA para todo.** El porcentaje es único (`joven_iva_pct`). Si hay productos con IVA distinto, hay que ampliar el modelo.

## 11. Dónde se ve

- **Configuración → Placeta Joven:** el porcentaje de IVA.
- **Registros:** creación de cuentas, marcas de comercio y compras.

## 12. Banco propietario, congelación y solo lectura (migración 0068)

**Dueño de las cuentas.** Todas las cuentas Placeta Joven pertenecen a **Banco de La Placeta**, aunque el titular sea una persona. El banco debe existir con ese nombre exacto (créalo en Bancos); si falta, las operaciones fallan con «Falta el banco "Banco de La Placeta"».

**Quién puede hacer qué:**

| Acción | Banco de La Placeta | Otros bancos |
|---|---|---|
| Crear la cuenta de un DIP | Sí | No |
| Comprar, recargar, congelar | Sí | **No** (se rechaza en la base de datos) |
| Leer estado, saldo y movimientos (`joven:leer`) | Sí | Sí, **solo lectura**, si la Junta les concede el permiso |

**Congelar.** Placeta Joven congela la cuenta cuando la suscripción no está al día:

- `POST /api/v1/bk/joven/cuentas/{iban}/congelar` con `{ "congelada": true, "motivo": "…" }` (motivo de al menos 10 caracteres).
- Mientras esté congelada, **ningún movimiento** es posible: ni compras, ni recargas, ni transferencias, ni ningún otro que la toque. La base de datos lo comprueba en cada transacción.
- Para reactivarla: `"congelada": false`.

**Leer.** `GET /api/v1/bk/joven/cuentas/{iban}` devuelve estado, congelación, motivo y disponible. No devuelve el DIP. Los movimientos (`.../movimientos`) también son de solo lectura.

**Garantía en la base de datos.** Ningún movimiento sobre una cuenta Joven puede salir sin la marca de Placeta Joven, aunque alguien llame a una función interna por otro camino. Por eso, un banco que intente operar por una ruta genérica recibe el error «Las cuentas Placeta Joven solo se operan desde Placeta Joven».

**Permisos.** Solo el cliente de Banco de La Placeta debe tener `joven:gestionar`. Los demás bancos, como mucho, `joven:leer`.

### Límites nuevos (léelos antes de publicar)

- **Lectura entre bancos.** Cualquier banco con `joven:leer` puede ver el saldo y los movimientos de **cualquier** cuenta Joven, aunque no sea suya. Es lo que se pidió, pero es una decisión de privacidad: la Junta debe valorar si se limita a los clientes de cada banco.
- **Reversiones de compras.** Una reversión de una compra Joven no puede hacerse por la ruta genérica (la marca Joven la bloquea). Hay que añadir un camino específico si se necesita.
- **Lo que no está verificado.** Como todo este módulo, la regla de bloqueo no se ha probado todavía en PostgreSQL.

## 13. Edad y periodo de gracia (migración 0069)

**Quién puede tener una cuenta Placeta Joven:** personas de **16 a 31 años**.

**Periodo de gracia.** La persona sigue siendo elegible hasta el **31 de diciembre del año en que cumple 31 años**. Después, la cuenta se congela sola.

Ejemplos:

| Fecha de nacimiento | Puede abrir la cuenta | Elegible hasta |
|---|---|---|
| 2010-05-03 | Sí, desde el 3 de mayo de 2026 (cumple 16) | 31 de diciembre de 2041 |
| 1995-06-01 | No: cumplió 31 en 2026 y debe abrirla dentro de su año de gracia, que termina el 31 de diciembre de 2026 | 31 de diciembre de 2026 |
| 1980-01-15 | No: está fuera de la edad | — |

**Cuándo se comprueba:**
1. **Al abrir la cuenta** (`POST /api/v1/bk/joven/cuentas` con `fecha_nacimiento`). Sin fecha verificada, no se abre.
2. **En cada compra y recarga.** Si la persona ya no es elegible, la operación se rechaza aunque la cuenta no esté congelada.
3. **Cada día.** El proceso diario congela las cuentas de quienes han dejado de ser elegibles, con el motivo en la cuenta.

**Descongelar.** No se puede descongelar a quien ya no es elegible: la API lo rechaza.

**Lectura.** `GET /api/v1/bk/joven/cuentas/{iban}` indica `elegible: true o false`, sin mostrar la fecha de nacimiento ni el DIP.

**Cuentas creadas antes de esta versión** no tienen fecha de nacimiento verificada: no pueden comprar ni recargar hasta que se registre su fecha con el alta.

### Límites
- La fecha de nacimiento la proporciona el banco. Placeta Joven no la verifica con documentos.
- La regla no se ha probado todavía en PostgreSQL.
