# Liquidación interbancaria y tasas (estado y decisiones)

## Decisiones aprobadas
1. **Liquidación neta diaria.** Cada día se calcula la posición neta entre cada par de bancos y se liquida. La liquidación es todo o nada.
2. **Cada banco financia su cuenta de liquidación** ("Liquidación interbancaria"). Si no tiene saldo, la liquidación del día no se ejecuta. Límite de exposición por par de bancos: si se supera, los pagos interbancarios nuevos se rechazan hasta liquidar.
3. **Las liquidaciones erróneas no se borran.** Se revierten con una liquidación compensatoria. Requiere dos personas distintas: quien pide y quien aprueba.
4. **Tasas: paga siempre el banco emisor.** Se aplican a transferencias interbancarias y a cargos de tarjeta de empresa. Las operaciones dentro de la misma entidad no pagan tasa.
5. **Solo cargos de tarjeta de empresa.** Las tarjetas personales y las RBU quedan exentas.

## Estado técnico (importante)
- **Migración 0040: escrita y comprobada estáticamente. NO ejecutada en PostgreSQL.** En el entorno de desarrollo no hay PostgreSQL ni red, así que no se ha podido probar.
- **Todo empieza apagado.** `plone27_config_interbancaria`: `liquidacion_activa = false`, `tasas_operaciones_activas = false`.
- **Límite de exposición:** si un par no tiene límite configurado, no hay límite (decisión por defecto; revísala).
- **Conexión (migración 0041): hecha en código, NO probada.** Transferencias de usuario (`plone27_user_transfer`), cargos de tarjeta liquidados por el banco (`plone27_bk_card_settle`, solo tarjetas de empresa) y cobro de deudas (`plone27_debt_pay`, sin tasa) registran la operación interbancaria. Las tasas se cobran solo con el interruptor activo. Las liquidaciones de pagos de la pasarela con tarjeta no pasan por la tasa de cargo, para no cobrar dos veces.
- **Pendiente de conectar:** nómina, gastos institucionales, ventas, reembolsos, RBU y cobros de plan no registran operación interbancaria todavía.
- (Anterior, ya resuelto por 0041:) Tasas NO conectadas a las transferencias ni a los cargos. `plone27_cobrar_tasa` existe, pero las funciones que mueven dinero (`plone27_user_transfer`, `plone27_bk_card_settle` y las demás que llaman a `plone27_transfer`) todavía no la llaman. Conectarla exige modificar esas funciones y probarlas: queda como siguiente paso.
- Los registros de operaciones interbancarias llegan desde los pagos de la pasarela (vía disparador). Las transferencias normales no se registran hasta que se conecten.
- Pendiente de configurar en Vercel Cron: `GET /api/cron/liquidacion` una vez al día, con `Authorization: Bearer $CRON_SECRET`.

## Prueba antes de activar nada
1. Ejecutar `plone27_setup_completo.sql` en una base de pruebas. Corregir cualquier error.
2. Crear dos entidades con pasarela activa y cuentas de empresa en cada una.
3. Financiar la cuenta de liquidación de cada entidad (con una transferencia de prueba).
4. Activar **solo** la liquidación. Generar pagos interbancarios de prueba. Ejecutar la liquidación del día. Comprobar que las dos cuentas de liquidación cuadran.
5. Probar un saldo insuficiente: la liquidación debe fallar entera, sin movimientos parciales.
6. Probar la reversión: solicitar con una persona y aprobar con otra. Probar que la misma persona no puede aprobar.
7. Probar el límite de exposición: con un límite bajo, el pago interbancario nuevo debe rechazarse.
8. Solo después, activar tasas en la base de pruebas, y repetir las pruebas de movimientos.
