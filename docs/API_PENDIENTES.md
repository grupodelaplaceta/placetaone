# API pendientes · análisis completo

Estado de la revisión: inventario automático de rutas (`src/app/api`) frente a las funciones SQL (`plone27_*`).

## Resumen

- **Funciones SQL:** 205. Hay 65 usadas por alguna ruta. Las 140 restantes son sobre todo auxiliares (guardas, cálculos internos, disparadores y procesos automáticos). Entre ellas hay unas cuarenta de negocio que no tienen ruta.
- **Lo que más falta:** pagos del usuario (recibos fiscales y deudas), disputas, cargos de tarjeta del usuario, nóminas propias, derechos del usuario (exportar datos), configuración de webhooks por el banco y listado de cuentas de la entidad.
- **Deuda técnica:** la especificación OpenAPI y la colección de Postman no incluyen ~25 rutas nuevas; las rutas raíz `/accounts` y `/transfers` son de personal y se confunden con las de banco; y la ruta genérica `/rpc/[fn]` necesita una revisión de su lista de funciones permitidas.

## Criterios de prioridad

- **P1:** mueve dinero, es un derecho del consumidor o del titular de datos, o bloquea la integración de bancos.
- **P2:** control operativo del banco o funciones avanzadas de usuario.
- **P3:** comodidad y analítica.

## A · API de bancos (servidor, `/api/v1/bk/…`)

| Ruta propuesta | Método | Función SQL existente | Permiso | Prioridad | Notas y riesgos |
|---|---|---|---|---|---|
| `/bk/cuentas` | GET | (vista filtrada por `bank_id`) | `accounts:read` | P1 | Hoy el banco solo crea cuentas o consulta una por IBAN. Sin listado no puede conciliar. |
| `/bk/webhooks` | GET, POST | tabla `plone27_webhooks` | `webhooks:gestionar` | P1 | La pasarela depende de webhooks, y hoy su configuración solo está en el panel. El secreto se devuelve **una sola vez**. |
| `/bk/webhooks/{id}/rotar` | POST | (nuevo) | `webhooks:gestionar` | P1 | Rota el secreto sin perder la configuración. |
| `/bk/webhooks/entregas` | GET | `plone27_outbox` | `webhooks:gestionar` | P1 | Ver entregas fallidas. |
| `/bk/webhooks/entregas/{id}/reintentar` | POST | (nuevo) | `webhooks:gestionar` | P2 | Reintento manual de una entrega fallida. |
| `/bk/tarjetas` | POST | `plone27_issue_card` | `tarjetas:emitir` | P1 | Emisión de tarjeta a un cliente de la entidad. Requiere reglas de tipo y de límite. |
| `/bk/tarjetas/{ref}/estado` | POST | `plone27_card_set_status` | `tarjetas:gestionar` | P1 | Bloqueo o cierre por el banco. Motivo obligatorio. |
| `/bk/cuentas/{iban}/tarjetas` | GET | `cards` (tabla) | `cards:read` | P2 | Listado de tarjetas de sus cuentas. |
| `/bk/tarjetas/cargos` | GET | `plone27_card_charges` | `tarjetas:cobrar` | P2 | Hoy no hay ninguna API de consulta de cargos. |
| `/bk/reservas` | POST, GET | `plone27_reserve` | `reservas:gestionar` | P2 | Retenciones de saldo (hoteles, alquileres). |
| `/bk/reservas/{id}/liberar` | POST | `plone27_release` | `reservas:gestionar` | P2 | Liberación de la retención. |
| `/bk/ventas` | POST | `plone27_sale` | `ventas:registrar` | P2 | Registro de ventas de comercios. Alimenta el IVA y la presunción de ventas. |
| `/bk/disputas` | GET, POST | `plone27_dispute_open` | `disputas:gestionar` | P1 | Apertura y consulta desde el lado del banco. |
| `/bk/disputas/{id}/resolver` | POST | `plone27_dispute_resolve` | `disputas:resolver` | P1 | Resolución con motivo. Debe quedar auditada y no debe permitir resolver la propia disputa. |
| `/bk/reversiones` | POST | `plone27_reverse` | `movimientos:revertir` | P2 | Anular un movimiento por error. **Requiere aprobación de un segundo usuario.** |
| `/bk/deudas` | GET | `plone27_debts` | `deudas:read` | P2 | Consulta de deudas reconocidas. |
| `/bk/recibos` | GET | `plone27_tax_receipts` | `recibos:read` | P2 | Recibos fiscales de los clientes de la entidad. |
| `/bk/movimientos` | GET | `plone27_transactions` | `movimientos:read` | P2 | Movimientos de todas las cuentas de la entidad, con filtros de fecha y tipo. |
| `/bk/planes/solicitudes` | POST | `plone27_approval_request` + `plone27_plan_create` | `planes:solicitar` | P2 | **El banco solicita; el personal aprueba.** No crea el plan directamente, porque `plone27_plan_create` exige `p_approved_by`. |
| `/bk/suscripciones/solicitudes` | POST | `plone27_approval_request` + `plone27_sub_create` | `planes:solicitar` | P2 | Igual que los planes. |
| `/bk/nominas/solicitudes` | POST | `plone27_approval_request` + `plone27_contract_create` | `nominas:solicitar` | P2 | Igual que los planes. |
| `/bk/checkouts` (lista) | GET | `plone27_checkouts` | `checkout:crear` | P2 | Listado con filtros de estado y fecha. |
| `/bk/credenciales/rotar` | POST | `plone27_api_clients` (clave) | `credenciales:rotar` | P2 | Hoy solo el panel puede rotar claves. Debe confirmarse con un segundo factor cuando exista. |
| `/bk/permisos` | GET | `plone27_api_clients` | cualquiera | P3 | El banco consulta sus propios permisos y límites. |
| `/bk/previsiones` | GET | `plone27_cash_forecast` | `analitica:read` | P3 | Previsión de caja de la entidad. |
| `/bk/estadisticas` | GET | `plone27_estadisticas_dia` | `analitica:read` | P3 | Estadísticas diarias. |

## B · API de usuario (web y app, `/api/v1/me/…`)

| Ruta propuesta | Método | Función SQL existente | Permiso | Prioridad | Notas y riesgos |
|---|---|---|---|---|---|
| `/me/recibos/{ref}/pagar` | POST | `plone27_tax_pay`, `plone27_tax_pay_partial` | `me:transfer` | P1 | **Hoy el usuario ve sus recibos pero no puede pagarlos por API.** Pago total o parcial, con `Idempotency-Key`. |
| `/me/deudas` | GET | `plone27_debts` | `me:read` | P1 | Deudas reconocidas con su estado y plazo. |
| `/me/deudas/{id}/pagar` | POST | `plone27_debt_pay` | `me:transfer` | P1 | Pago de deuda, con `Idempotency-Key`. |
| `/me/disputas` | GET, POST | `plone27_dispute_open` | `me:disputas` | P1 | El usuario reclama un cargo. Tipo, motivo y movimiento obligatorios. |
| `/me/disputas/{id}` | GET | `plone27_disputes` | `me:disputas` | P1 | Estado y resolución. |
| `/me/accounts/{iban}/cards/{ref}/cargos` | GET | `plone27_card_charges` | `me:read` | P1 | Cargos de la tarjeta, con estado (autorizado, facturado, liquidado, liberado). |
| `/me/nominas` | GET | `plone27_payslips` | `me:read` | P1 | Nóminas del propio usuario como trabajador. Solo las suyas (`worker_user`). Verificar columnas de `plone27_payslips` antes de construir. |
| `/me/datos/exportacion` | POST, GET | (nuevo, agregado de tablas del usuario) | `me:datos` | P1 | Derecho de acceso y portabilidad. **Requiere revisión legal del formato y del plazo.** |
| `/sessions/renovar` | POST | `plone27_session_open` | token actual | P1 | Renovar el token sin volver a autenticar. Hoy solo se renueva creando una sesión nueva desde el servidor. |
| `/me/tarjetas` | POST | `plone27_card_order_step`, `plone27_issue_card` | `me:seguridad` | P2 | Pedir una tarjeta nueva o física. El alta la aprueba la entidad. |
| `/me/tarjetas/{ref}/renovar` | POST | `plone27_card_renew` | `me:seguridad` | P2 | Renovación de tarjeta caducada. |
| `/me/accounts/{iban}/limites` | GET, PUT | (tabla de límites) | `me:seguridad` | P2 | Límites que el propio usuario puede bajar (nunca subir por encima del banco). |
| `/me/accounts/{iban}/cerrar` | POST | (nuevo) | `me:seguridad` | P2 | Cierre de cuenta con saldo cero y sin cargos pendientes. |
| `/me/accounts/{iban}` | PATCH | tabla `accounts` | `me:read` | P3 | Renombrar la cuenta. |
| `/me/suscripciones/{id}/cancelar` | POST | **no existe** | `me:transfer` | P2 | No hay función de cancelación de suscripciones. Hay que definir la regla antes de crearla. |
| `/me/planes/{id}/cuotas/{seq}/pagar` | POST | (nuevo, a partir de `plone27_plans_collect`) | `me:transfer` | P2 | Adelanto de una cuota. |
| `/me/contratos` | GET | `plone27_contracts` | `me:read` | P2 | Contratos de nómina del propio trabajador. |
| `/me/actividades` | GET, POST | `plone27_activity_register` | `me:seguridad` | P2 | Alta de actividad económica (base del cálculo del IAEP). |
| `/me/declaraciones` | GET, POST | `plone27_tax_declare` | `me:fiscal` | P2 | Declaraciones propias. Respeta los umbrales de retención. |
| `/me/junior` | GET | `plone27_junior_profiles` | `me:read` | P2 | Perfil y controles de una cuenta Junior. |
| `/me/junior/{id}/controles` | PUT | (tabla de perfil Junior) | `me:tutor` | P2 | Solo el tutor autorizado. |
| `/me/ventas` | GET | `plone27_sales` | `me:read` | P3 | Ventas del propio comercio. |
| `/me/preferencias` | GET, PUT | (nuevo) | `me:read` | P3 | Canales de notificación. |
| `/me/actividad` | GET | `plone27_audit_log` (filtrado) | `me:read` | P3 | Historial de acciones sobre la propia cuenta. |

## C · Transversal y deuda técnica

| Asunto | Estado | Acción propuesta | Prioridad |
|---|---|---|---|
| Especificación OpenAPI | Faltan ~25 rutas nuevas | Generar desde las rutas, no a mano, y validar en CI | P1 |
| Colección de Postman | Igual que OpenAPI | Regenerar junto con OpenAPI | P1 |
| `/accounts` y `/transfers` (raíz) | Son de personal, no de banco | Mover a `/api/admin/…` para evitar confusiones | P2 |
| `/rpc/[fn]` | Lista de funciones permitidas | Revisar función por función; cada una con su rol y su motivo | P1 |
| Paginación | Algunas listas devuelven todo | Paginación por cursor en listados grandes | P2 |
| Códigos de error | Mensajes libres | Código estable y mensaje (`saldo_insuficiente`, `no_autorizado`…) | P2 |
| Límite de peticiones | **Aplicado** (`clientFrom`) | Documentar límites por cliente | P2 |
| Idempotencia | Aplicada en transferencias, cargos, diseños y pasarela | Aplicar a todo lo que mueva dinero, incluidos los pagos de recibos y deudas | P1 |

## D · Decisiones que necesito antes de construir

1. **Aprobación de planes, suscripciones y contratos.** ¿El banco solicita y el personal aprueba (cuatro ojos)? ¿Quién aprueba y en qué plazo?
2. **Disputas.** ¿Plazo para reclamar? ¿Quién resuelve, el banco o Placeta? ¿Hay reembolso automático por debajo de cierto importe?
3. **Cancelación de suscripciones.** ¿Efecto inmediato o al final del periodo ya pagado?
4. **Reversiones.** ¿Solo el personal, con aprobación de un segundo usuario?
5. **Límites del usuario.** ¿Qué límites puede bajar el usuario y cuáles solo el banco?
6. **Emisión de tarjetas por el banco.** ¿Qué tipos puede emitir cada entidad y con qué límites máximos?
7. **Exportación de datos (RGPD).** Formato, plazo y contenido. Debe revisarlo un abogado antes de construirlo.
8. **Cierre de cuenta.** ¿Qué pasa con las tarjetas, las programadas y las suscripciones vinculadas?

## E · Orden de construcción propuesto

**Fase 1 · dinero, derechos y bloqueos de integración (P1)**
- Pagos de recibos y deudas del usuario, con idempotencia.
- Cargos de tarjeta y deudas del usuario (consulta).
- Disputas: usuario y banco.
- Nóminas propias del trabajador.
- Exportación de datos (tras la revisión legal).
- Webhooks gestionados por el banco, y entregas fallidas.
- Listado de cuentas de la entidad.
- Renovación de sesión.
- Actualizar OpenAPI y Postman en la misma entrega.

**Fase 2 · control operativo (P2)**
- Emisión, bloqueo, renovación y pedido de tarjetas.
- Reservas y ventas.
- Planes, suscripciones y nóminas por solicitud con aprobación.
- Reversiones con cuatro ojos.
- Límites, cierre de cuenta, cancelación de suscripciones.
- Actividades, declaraciones, perfil Junior y tutor.

**Fase 3 · analítica y calidad (P3)**
- Previsiones y estadísticas para bancos.
- Preferencias, actividad y ventas propias.
- Unificación de rutas, paginación y códigos de error.

## F · Criterios de aceptación de cada endpoint

- **Pruebas de aislamiento:** un usuario o banco no puede leer ni operar sobre lo de otro (ya existe el script de aislamiento; hay que ampliarlo a cada ruta nueva).
- **Idempotencia:** repetir la misma petición con la misma clave no duplica el movimiento.
- **Permisos:** cada ruta comprueba el permiso antes de tocar datos.
- **Auditoría:** cada operación que cambia dinero o estado deja registro con el actor.
- **Especificación:** la ruta aparece en OpenAPI y en Postman con ejemplo de respuesta.
