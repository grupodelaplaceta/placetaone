# Sanciones: multas, incautaciones y embargos (migraciones 0072 y 0073)

> Poder sobre el dinero de las personas. Solo la Junta. No ejecutado en PostgreSQL.
> La Junta son cuatro personas y la mayoría no usa el sistema: **no hay doble aprobación**. La responsabilidad es de quien propone y ejecuta, y todo queda en la auditoría con su motivo.

## Tipos

| Tipo | Qué hace al ejecutarse | Destino |
|---|---|---|
| **Multa** | Cuentas personales y de tutor: se convierte en deuda que cobra el sistema (vence a los 15 días). Cuentas Joven: se cobra al momento. | Administración o tributos |
| **Incautación** | Transfiere el importe de la cuenta a la cuenta de destino. | Administración o tributos |
| **Embargo** | Reserva el importe sin moverlo, hasta que se levante. | — |

## Quién paga

- **Cuenta personal o empresa:** la propia cuenta.
- **Cuenta junior:** **la cuenta principal de su tutor.** La sanción guarda la cuenta junior de origen para la trazabilidad. Si el tutor no tiene cuenta personal en la entidad, o la cuenta junior no tiene tutor, la sanción se rechaza.
- **Cuenta Placeta Joven:** la propia cuenta Joven, **conforme a las normas de Placeta Joven**. Sus restricciones de circulación siguen vigentes: el destino solo puede ser administración o tributos. Puede tocar una cuenta congelada (la congelación es por suscripción y la sanción va por encima).
- **Cuentas de administración:** no pueden ser objeto de sanción.

## Flujo

1. **Proponer** (`POST /api/admin/justicia/sanciones`): motivo (mínimo 20 caracteres), norma que la respalda y, si procede, la cuenta de destino. La sanción queda **aprobada** al proponerla.
2. **Notificar**: abre el plazo para recurrir (30 días por defecto).
3. **Recurrir** (si la persona recurre dentro de plazo): la sanción queda parada.
4. **Resolver el recurso**: confirmar (queda firme) o anular.
5. Si no hay recurso dentro de plazo, pasa a **firme** sola cada día.
6. **Ejecutar**: aplica la multa, la incautación o el embargo.
7. **Levantar** (solo embargos): libera el dinero.

## Límites de protección

- **Saldo inembargable de 160 Pz** (ajuste `sancion_inembargable_pz`). Nunca se incauta, embarga ni cobra por debajo de esa cantidad. El resto sí puede.
- **Plazo de recurso:** 30 días (ajuste `sancion_plazo_recurso_dias`, entre 10 y 90). Mientras esté recurrida, no se ejecuta.
- **Destino de multas e incautaciones:** administración o tributos de la misma entidad.
- Todos los pasos quedan en la auditoría con el motivo.

## Lo que NO está hecho

- **No hay rol judicial propio.** Hoy solo la Junta opera las sanciones.
- **Retirar una denuncia** no está implementado.
- **El aviso a la persona no lo envía el sistema.** La Junta registra la notificación.
- **No hay canal propio para recurrir.** Lo registra la Junta en nombre de la persona.


## Actualización: avisos, denuncia, programación y revocación (migración 0074)

**Quién notifica.** Placeta **no envía correos**. Cada banco envía sus avisos con su propio Gmail. Placeta publica los avisos en `GET /api/v1/bk/avisos` (permiso `avisos:gestionar`) y el banco acusa recibo con `POST /api/v1/bk/avisos/{id}/acuse`.

**Tipos de aviso:** sanción notificada, ejecución prevista, cobro de multa previsto y sanción revocada.

**Antelación de 5 horas.** Ninguna ejecución se programa con menos de 5 horas. El aviso de ejecución se publica exactamente 5 horas antes de la hora programada. Las multas se cobran a las 04:00 UTC del día de vencimiento; su aviso se publica a las 23:00 UTC del día anterior.

**Programar.** `POST /api/admin/justicia/sanciones/{id}/programar` con `{ "fecha": "AAAA-MM-DDTHH:MM:SSZ" }`. Solo sanciones firmes.

**Ejecutar.** El proceso diario ejecuta las sanciones cuya hora programada ya ha llegado. Como el proceso corre a las 04:00 UTC, las ejecuciones programadas se hacen en el primer ciclo diario a partir de esa hora. Por eso conviene programarlas a las 04:00 UTC.

**Recurrir solo denunciando.** La persona sancionada o su tutor presentan denuncia a través de su banco: `POST /api/v1/bk/sanciones/{id}/denuncia` (permiso `justicia:denunciar`). La denuncia abre el recurso. Ya no existe la opción de recurrir desde la Junta. Debe presentarse dentro del plazo de 30 días desde la notificación, y solo la persona sancionada o su tutor pueden presentarla.

**Revocar.** `POST /api/admin/justicia/sanciones/{id}/revocar` con `{ "motivo": "…" }`. Deshace los efectos:
- **Incautación o multa a cuenta Joven ya cobrada:** devuelve el dinero con un movimiento contrario.
- **Embargo ejecutado:** libera el dinero.
- **Multa convertida en deuda:** si no tiene pagos, se marca como disputada, para que el cobro automático no la cobre. Si ya tiene pagos, hay que revertirlos antes.
- **Sanción aún no ejecutada:** se cancela sin más.

Todas las revocaciones generan un aviso para el banco.

**Lo que NO está hecho:**
- La **denuncia la presenta la persona a través de su banco**. Placeta no tiene canal propio para ello.
- **Retirar una denuncia** no está implementado.
- **El cobro automático de multas a cuentas personales no respeta todavía el saldo inembargable.**
- **Retirar una denuncia** no está implementado.


## Actualización: cobro inembargable y pantalla (migración 0075)

**Cobro de multas.** Las multas que se convierten en deuda son inembargables: el cobro automático solo toma lo que supere los 160 Pz de saldo protegido. Si el saldo está por debajo de ese mínimo, no se cobra ese día y se vuelve a intentar al siguiente. Las deudas que no son multas no cambian.

**Pantalla.** Menú **Sanciones** del panel: proponer, notificar, programar la ejecución (con 5 horas de antelación), confirmar o anular recursos, ejecutar, levantar embargos y revocar. Muestra el IBAN de la cuenta, la cuenta del tutor en los casos junior, el destino, los plazos y el número de denuncias.


## Actualización: el SMI es ajustable por la Junta (migración 0076)

- El **SMI mensual** (`smi_mensual_completa_pz`) lo cambia la Junta desde Configuración, con motivo, sin segunda persona. Queda en la auditoría.
- El **saldo inembargable** de las sanciones es el SMI mensual. Ya no tiene un valor propio: al cambiar el SMI, cambia el mínimo inembargable.
- El **control de contratos** ya lee el SMI mensual en cada alta: un contrato por debajo del nuevo SMI se rechaza.
- El **SMI semanal** (36,92) es solo informativo y no se actualiza solo.
- La lista de preparación de la instalación (una consulta de diagnóstico, no una función del sistema) sigue mostrando «160 Pz»; no afecta al funcionamiento.


## Actualización: denuncias ante Justicia, externa (migración 0077)

**Justicia no es un banco.** Es un organismo externo. Las denuncias se presentan ante Justicia, no a través de la entidad de la persona. Por eso:

- **Los bancos ya no pueden presentar denuncias.** La ruta de denuncia de banca se ha retirado.
- **Justicia es una entidad propia** en el sistema, llamada «Justicia (externo)», sin cuentas de dinero. Tiene su propia clave, con el permiso `justicia:denunciar`. Esa entidad la crea la Junta desde Bancos.
- **Justicia registra la denuncia** con `POST /api/v1/justicia/denuncias` `{ sancion, dip, texto }`. Eso abre el recurso de la sanción, dentro del plazo de 30 días desde la notificación.
- **Justicia consulta las sanciones** de una persona con `GET /api/v1/justicia/sanciones?dip=…`: solo las notificadas con plazo abierto.
- **Los bancos siguen recibiendo los avisos** (sanción notificada, ejecución prevista, cobro de multa y revocación) para comunicarlos a sus clientes con su propio Gmail.

Solo la persona sancionada o su tutor pueden denunciar. Justicia debe comprobarlo antes de presentar la denuncia; el sistema verifica que el DIP corresponda.
