# Quién gestiona qué: panel de la Junta frente a API de cada banco

## Principio
- **Panel de Placeta (rol admin = Junta):** solo las decisiones que afectan a toda la plataforma.
- **API de cada banco:** todo lo que gestiona su propia organización. Sin el panel, un banco puede operar por completo.

## Qué queda en el panel de la Junta
| Área | Por qué es de la Junta |
|---|---|
| Alta y aprobación de bancos (`api-bancos`) | Decide quién entra en la plataforma |
| Tarifa propietaria de tasas y de comisiones | Precio que cobra la plataforma |
| Liquidación interbancaria y reversiones | Dinero entre bancos |
| Parámetros de plazos y umbrales de reclamaciones | Reglas comunes |
| Categorías de comercio | Catálogo común |
| Estado global de la plataforma (salud, infraestructura, IVA, análisis) | Operación de la plataforma |

## Qué se gestiona desde la API del banco
| Área | Ruta |
|---|---|
| Claves de API de la entidad | `/api/v1/bk/clientes` |
| Empresas, titulares, pasarela, contrato, NFC, estado, ficha | `/api/v1/bk/empresas/...` |
| Organigrama: unidades, puestos, nombramientos, ceses, permisos, delegaciones, cierres | `/api/v1/bk/organigrama` |
| Presupuestos, planes, reasignaciones | `/api/v1/bk/presupuestos/...` |
| Nóminas y periodos | `/api/v1/bk/nominas`, `/api/v1/bk/nominas/periodos` |
| Gastos, tareas, fondos, convocatorias, solicitudes | `/api/v1/bk/gastos`, `/tareas`, `/fondos`, `/convocatorias`, `/solicitudes` |
| Subvenciones: programas, concesiones, justificaciones, pagos | `/api/v1/bk/programas`, `/justificaciones` |
| Reglas de uso (RBU y subvenciones) | `/api/v1/bk/politicas` |
| Pasarela, pagos, código de pago, restricciones, comisiones, tasas | `/api/v1/bk/pagos`, `/restricciones`, `/comisiones`, `/tasas` |
| Reclamaciones de deudas (como acreedor) | `/api/v1/bk/disputas` |
| Branding, webhooks, entregas | `/api/v1/bk/branding`, `/webhooks` |

## Cambios de esta entrega
- **El panel solo acepta el rol `admin`.** El resto del personal de Placeta no entra al panel. Quien tenga otro rol debe operar desde la API de su banco.
- Nuevos permisos: `clientes:gestionar` y `disputas:gestionar`. Los bancos los conceden a sus propias claves.
- Organigrama por API: delegar y revocar delegaciones (antes solo estaban en el panel).

## Consecuencias que debes conocer
- Las pantallas del panel que gestionaban la operativa de cada banco (empresas, institucional, pagos y reglas, financiación, comercios de operación) quedan **solo para la Junta**. Para la operativa diaria, cada banco usa su API.
- Las reclamaciones del banco acreedor se resuelven desde la API del banco, no desde el panel.
- Antes de desplegar, confirma que las cuentas de la Junta tienen el rol `admin` en `plone27_staff`. Si no, nadie podrá entrar al panel.

## Estado
- Migración 0046 y rutas nuevas: escritas y comprobadas estáticamente. **No ejecutadas en PostgreSQL.**
- Pendiente: la API de banco no permite todavía listar las deudas de sus clientes ni cambiar las reglas de tasas de la Junta (correcto: son de la Junta).
