# Inventario de la API (Art. 13 del Manual DEVAI)

Generado el 2026-11-19 desde `src/app/api/**/route.ts`. Rutas: **160**. Sin autenticación detectada: **0**. Públicas con justificación: **3**.

Cada ruta usa uno de estos mecanismos. Las rutas públicas están justificadas en la columna de autenticación. El contrato completo está en `docs/openapi.json`.

| Ruta | Métodos | Autenticación / permiso |
|---|---|---|
| `/api/accounts` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/analisis` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/api-bancos` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/clients/[id]/rotate` | POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/clients` | POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/comercios` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/comisiones` | POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/disputas` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/empresas` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/health` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/infra` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/institucional` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/iva` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/liquidacion` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/operaciones` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/organigrama` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/overview` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/pasarela` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/previsiones` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/r/[res]` | DELETE,GET,PATCH,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/settings` | GET | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/admin/tasas` | GET,POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/checkout/[token]/cancelar` | POST | Público por token de pago (256 bits, caduca en 3 a 30 min) |
| `/api/checkout/[token]` | GET | Público por token de pago (256 bits, caduca en 3 a 30 min) |
| `/api/cron/alerts` | GET | Cron: `Authorization: Bearer CRON_SECRET` |
| `/api/cron/finanzas` | GET | Cron: `Authorization: Bearer CRON_SECRET` |
| `/api/cron/liquidacion` | GET | Cron: `Authorization: Bearer CRON_SECRET` |
| `/api/cron/webhooks` | GET | Cron: `Authorization: Bearer CRON_SECRET` |
| `/api/public-config` | GET | Público: solo URL y clave anónima (públicas por diseño) |
| `/api/rpc/[fn]` | POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/transfers` | POST | Panel de la Junta: personal con rol `admin` (`staffFrom`) |
| `/api/v1/accounts/[iban]/cards` | GET | API de banco: clave x-api-key, permiso `cards:read` |
| `/api/v1/accounts/[iban]/membership/renew` | POST | API de banco: clave x-api-key, permiso `memberships:write` |
| `/api/v1/accounts/[iban]/membership` | GET | API de banco: clave x-api-key, permiso `memberships:read` |
| `/api/v1/accounts/[iban]/receipts` | GET | API de banco: clave x-api-key, permiso `receipts:read` |
| `/api/v1/accounts/[iban]` | GET | API de banco: clave x-api-key, permiso `accounts:read` |
| `/api/v1/accounts/[iban]/transactions` | GET | API de banco: clave x-api-key, permiso `transactions:read` |
| `/api/v1/accounts` | POST | API de banco: clave x-api-key, permiso `accounts:write` |
| `/api/v1/bk/branding/logo` | POST | API de banco: clave x-api-key, permiso `branding:gestionar` |
| `/api/v1/bk/branding` | GET,PUT | API de banco: clave x-api-key, permiso `branding:gestionar` |
| `/api/v1/bk/categorias` | GET | API de banco: clave x-api-key, permiso `politicas:gestionar` |
| `/api/v1/bk/checkouts/[id]` | GET | API de banco: clave x-api-key, permiso `checkout:crear` |
| `/api/v1/bk/checkouts` | GET,POST | API de banco: clave x-api-key, permiso `checkout:crear` |
| `/api/v1/bk/clientes/[id]/desactivar` | POST | API de banco: clave x-api-key, permiso `clientes:gestionar` |
| `/api/v1/bk/clientes/[id]/rotar` | POST | API de banco: clave x-api-key, permiso `clientes:gestionar` |
| `/api/v1/bk/clientes` | GET,POST | API de banco: clave x-api-key, permiso `clientes:gestionar` |
| `/api/v1/bk/comercio/branding` | PUT | API de banco: clave x-api-key, permiso `branding:gestionar` |
| `/api/v1/bk/comercio/logo` | POST | API de banco: clave x-api-key, permiso `branding:gestionar` |
| `/api/v1/bk/comercios` | GET | API de banco: clave x-api-key, permiso `politicas:gestionar` |
| `/api/v1/bk/comisiones` | GET,PUT | API de banco: clave x-api-key, permiso `comisiones:configurar` |
| `/api/v1/bk/convocatorias` | POST | API de banco: clave x-api-key, permiso `convocatorias:gestionar` |
| `/api/v1/bk/cuentas` | GET | API de banco: clave x-api-key, permiso `accounts:read` |
| `/api/v1/bk/disputas/[id]/resolver` | POST | API de banco: clave x-api-key, permiso `disputas:gestionar` |
| `/api/v1/bk/disputas` | GET | API de banco: clave x-api-key, permiso `disputas:gestionar` |
| `/api/v1/bk/empresas/[id]/asegurar-entidad` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/complementos/asignaciones/[asig]/retirar` | POST | API de banco: clave x-api-key, permiso `retribuciones:gestionar` |
| `/api/v1/bk/empresas/[id]/complementos/asignaciones` | POST | API de banco: clave x-api-key, permiso `retribuciones:gestionar` |
| `/api/v1/bk/empresas/[id]/complementos` | GET,POST | API de banco: clave x-api-key, permiso `nominas:read` |
| `/api/v1/bk/empresas/[id]/contrato` | GET | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/cuentas` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/datos` | PUT | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/entidad/crear` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/entidad` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/estado` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/ficha` | GET | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/nomina/conceptos` | GET | API de banco: clave x-api-key, permiso `nominas:read` |
| `/api/v1/bk/empresas/[id]/nomina/recibos` | GET | API de banco: clave x-api-key, permiso `nominas:read` |
| `/api/v1/bk/empresas/[id]/pasarela/rotar` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/pasarela` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]` | GET | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/titulares/cese` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas/[id]/titulares` | POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/empresas` | GET,POST | API de banco: clave x-api-key, permiso `empresas:gestionar` |
| `/api/v1/bk/entidad/configuracion` | PUT | API de banco: clave x-api-key, permiso `entidad:configurar` |
| `/api/v1/bk/expedientes` | GET | API de banco: clave x-api-key, permiso `retribuciones:gestionar` |
| `/api/v1/bk/fondos` | POST | API de banco: clave x-api-key, permiso `presupuestos:gestionar` |
| `/api/v1/bk/gastos/[id]/accion` | POST | API de banco: clave x-api-key, permiso `gastos:gestionar` |
| `/api/v1/bk/gastos` | POST | API de banco: clave x-api-key, permiso `gastos:gestionar` |
| `/api/v1/bk/interbancarias/posicion` | GET | API de banco: clave x-api-key, permiso `interbancarias:gestionar` |
| `/api/v1/bk/interbancarias` | GET | API de banco: clave x-api-key, permiso `interbancarias:gestionar` |
| `/api/v1/bk/justificaciones/[id]/pagar` | POST | API de banco: clave x-api-key, permiso `subvenciones:gestionar` |
| `/api/v1/bk/justificaciones/[id]/rechazar` | POST | API de banco: clave x-api-key, permiso `subvenciones:gestionar` |
| `/api/v1/bk/justificaciones` | GET,POST | API de banco: clave x-api-key, permiso `subvenciones:gestionar` |
| `/api/v1/bk/link-account` | POST | API de banco: clave x-api-key, permiso `usuarios:gestionar` |
| `/api/v1/bk/nominas/periodos` | POST | API de banco: clave x-api-key, permiso `nominas:generar` |
| `/api/v1/bk/nominas` | GET | API de banco: clave x-api-key, permiso `nominas:read` |
| `/api/v1/bk/organigrama` | GET,POST | API de banco: clave x-api-key, permiso `organigrama:leer` |
| `/api/v1/bk/origenes` | DELETE,GET,POST | API de banco: clave x-api-key, permiso `origenes:gestionar` |
| `/api/v1/bk/pagos/[id]/resolucion` | POST | API de banco: clave x-api-key, permiso `pagos:resolver` |
| `/api/v1/bk/pagos/canjear` | POST | API de banco: clave x-api-key, permiso `pagos:resolver` |
| `/api/v1/bk/pagos` | GET | API de banco: clave x-api-key, permiso `pagos:resolver` |
| `/api/v1/bk/pasarela` | GET,PUT | API de banco: clave x-api-key, permiso `pasarela:configurar` |
| `/api/v1/bk/personas` | GET | API de banco: clave x-api-key, permiso `personas:buscar` |
| `/api/v1/bk/planes` | GET | API de banco: clave x-api-key, permiso `planes:read` |
| `/api/v1/bk/politicas/[id]/desactivar` | POST | API de banco: clave x-api-key, permiso `politicas:gestionar` |
| `/api/v1/bk/politicas` | GET,POST | API de banco: clave x-api-key, permiso `politicas:gestionar` |
| `/api/v1/bk/presupuestos/mensual` | POST | API de banco: clave x-api-key, permiso `presupuestos:gestionar` |
| `/api/v1/bk/presupuestos/planes` | POST | API de banco: clave x-api-key, permiso `presupuestos:gestionar` |
| `/api/v1/bk/presupuestos/reasignaciones` | POST | API de banco: clave x-api-key, permiso `presupuestos:gestionar` |
| `/api/v1/bk/presupuestos` | GET,PUT | API de banco: clave x-api-key, permiso `presupuestos:leer` |
| `/api/v1/bk/programas/[id]/concesiones` | GET,POST | API de banco: clave x-api-key, permiso `subvenciones:gestionar` |
| `/api/v1/bk/programas` | GET,POST | API de banco: clave x-api-key, permiso `subvenciones:gestionar` |
| `/api/v1/bk/recurrentes/generar` | POST | API de banco: clave x-api-key, permiso `recurrentes:gestionar` |
| `/api/v1/bk/recurrentes` | POST | API de banco: clave x-api-key, permiso `recurrentes:gestionar` |
| `/api/v1/bk/restricciones` | GET,PUT | API de banco: clave x-api-key, permiso `pagos:restringir` |
| `/api/v1/bk/retribuciones` | POST | API de banco: clave x-api-key, permiso `retribuciones:gestionar` |
| `/api/v1/bk/solicitudes/[id]/resolver` | POST | API de banco: clave x-api-key, permiso `solicitudes:gestionar` |
| `/api/v1/bk/solicitudes` | POST | API de banco: clave x-api-key, permiso `solicitudes:gestionar` |
| `/api/v1/bk/tareas/[id]/accion` | POST | API de banco: clave x-api-key, permiso `tareas:gestionar` |
| `/api/v1/bk/tareas` | POST | API de banco: clave x-api-key, permiso `tareas:gestionar` |
| `/api/v1/bk/tarjetas/[ref]/nfc` | GET,PUT | API de banco: clave x-api-key, permiso `tarjetas:gestionar` |
| `/api/v1/bk/tarjetas/cargos/[id]/liberar` | POST | API de banco: clave x-api-key, permiso `tarjetas:cobrar` |
| `/api/v1/bk/tarjetas/cargos/[id]/liquidar` | POST | API de banco: clave x-api-key, permiso `tarjetas:cobrar` |
| `/api/v1/bk/tarjetas/cargos` | POST | API de banco: clave x-api-key, permiso `tarjetas:cobrar` |
| `/api/v1/bk/tasas/[id]/desactivar` | POST | API de banco: clave x-api-key, permiso `tasas:gestionar` |
| `/api/v1/bk/tasas` | GET,POST | API de banco: clave x-api-key, permiso `tasas:gestionar` |
| `/api/v1/bk/tipos-destino` | GET | API de banco: clave x-api-key, permiso `politicas:gestionar` |
| `/api/v1/bk/webhooks/[id]/rotar` | POST | API de banco: clave x-api-key, permiso `webhooks:gestionar` |
| `/api/v1/bk/webhooks/[id]` | DELETE | API de banco: clave x-api-key, permiso `webhooks:gestionar` |
| `/api/v1/bk/webhooks/entregas/[id]/reintentar` | POST | API de banco: clave x-api-key, permiso `webhooks:gestionar` |
| `/api/v1/bk/webhooks/entregas` | GET | API de banco: clave x-api-key, permiso `webhooks:gestionar` |
| `/api/v1/bk/webhooks` | GET,POST | API de banco: clave x-api-key, permiso `webhooks:gestionar` |
| `/api/v1/designs` | GET | API de banco: clave x-api-key, permiso `products:read` |
| `/api/v1/me/accounts/[iban]/cards` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/accounts/[iban]/receipts` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/accounts/[iban]` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/accounts/[iban]/statement` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/accounts/[iban]/transactions` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/accounts` | GET,POST | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/beneficiaries/[id]` | DELETE | API de usuario: token `pus_`, permiso `me:transfer` |
| `/api/v1/me/beneficiaries` | GET,POST | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/cards/[ref]/diseno` | POST | API de usuario: token `pus_`, permiso `me:seguridad` |
| `/api/v1/me/cards/[ref]` | POST | API de usuario: token `pus_`, permiso `me:seguridad` |
| `/api/v1/me/designs/[codigo]/buy` | POST | API de usuario: token `pus_`, permiso `me:transfer` |
| `/api/v1/me/designs/comprados` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/designs` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/deudas/[id]/disputa` | POST | API de usuario: token `pus_`, permiso `me:disputas` |
| `/api/v1/me/deudas/[id]/pagar` | POST | API de usuario: token `pus_`, permiso `me:transfer` |
| `/api/v1/me/deudas` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/disputas` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/exportar` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/lookup` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/notifications/read` | POST | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/notifications` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/plans` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/previsiones` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/rbu/[id]/claim` | POST | API de usuario: token `pus_`, permiso `me:transfer` |
| `/api/v1/me/rbu` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/rbu/saldo` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/receipts/[ref]/certificate` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/requests` | GET,POST | API de usuario: token `pus_`, permiso `me:contratar` |
| `/api/v1/me` | GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/sessions` | DELETE,GET | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/me/transfers` | POST | API de usuario: token `pus_`, permiso `me:transfer` |
| `/api/v1/me/transfers/scheduled/[id]` | DELETE | API de usuario: token `pus_`, permiso `me:transfer` |
| `/api/v1/me/transfers/scheduled` | GET,POST | API de usuario: token `pus_`, permiso `me:read` |
| `/api/v1/products` | GET | API de banco: clave x-api-key, permiso `products:read` |
| `/api/v1/sessions` | DELETE,POST | Servidor del banco: clave + firma HMAC + nonce (y token `pus_` para cerrar sesión) |
| `/api/v1/transfers/[ref]` | GET | API de banco: clave x-api-key, permiso `transfers:read` |
| `/api/v1/transfers` | POST | API de banco: clave x-api-key, permiso `transfers:write` |
