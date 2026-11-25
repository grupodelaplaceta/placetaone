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

- **El cobro automático de multas a cuentas personales no respeta todavía el saldo inembargable.** Una multa convertida en deuda puede cobrarse entera. Hay que ajustar el cobro automático antes de usar multas en producción.
- **No hay rol judicial propio.** Hoy solo la Junta opera las sanciones.
- **No hay pantalla en el panel.** Las sanciones se gestionan por API.
- **El aviso a la persona no lo envía el sistema.** La Junta registra la notificación.
- **No hay canal propio para recurrir.** Lo registra la Junta en nombre de la persona.
