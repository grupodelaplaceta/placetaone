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
