# Sanciones: multas, incautaciones y embargos (migración 0072)

> Poder sobre el dinero de las personas. Solo la Junta, con doble firma en cada paso. No ejecutado en PostgreSQL.

## Tipos

| Tipo | Qué hace al ejecutarse | Destino |
|---|---|---|
| **Multa** | Crea una deuda de la persona a favor de la administración. La cobra el sistema con el cobro automático de deudas. Vence a los 15 días. | Cuenta de administración |
| **Incautación** | Transfiere el importe de la cuenta de la persona a la cuenta de administración. | Cuenta de administración |
| **Embargo** | Reserva el importe en la cuenta, sin moverlo, hasta que se levante. | — |

## Flujo (cada paso lo hace una persona distinta)

1. **Proponer** (`POST /api/admin/justicia/sanciones`): motivo (mínimo 20 caracteres) y norma que la respalda.
2. **Aprobar** (otra persona de la Junta).
3. **Notificar**: abre el plazo para recurrir (30 días por defecto).
4. **Recurrir** (si la persona recurre dentro de plazo): la sanción queda parada.
5. **Resolver el recurso** (otra persona): confirmar (queda firme) o anular.
6. Si no hay recurso dentro de plazo, pasa a **firme** sola cada día.
7. **Ejecutar** (otra persona distinta de quien propuso): aplica la multa, la incautación o el embargo.
8. **Levantar** (solo embargos): libera el dinero.

## Límites de protección

- **Saldo inembargable:** nunca se incauta ni embarga por debajo de 160 Pz (ajuste `sancion_inembargable_pz`). El resto del saldo sí puede.
- **Cuentas Joven y de administración no pueden ser objeto de sanción.**
- **Cuentas de destino:** solo de administración de la misma entidad.
- **Plazo de recurso:** 30 días (ajuste `sancion_plazo_recurso_dias`, entre 10 y 90). Mientras esté recurrida, no se ejecuta.
- Todos los pasos quedan en la auditoría con el motivo.

## Lo que NO está hecho (decisión pendiente)

- **El cobro automático de multas no respeta todavía el saldo inembargable.** Una multa convertida en deuda puede cobrarse por completo. Hay que ajustar el cobro automático antes de usar multas en producción.
- **No hay rol judicial propio.** Hoy solo la Junta (rol admin) opera las sanciones. Un rol de justicia separado es una decisión pendiente.
- **No hay pantalla en el panel.** Las sanciones se gestionan por API. La pantalla es el siguiente paso.
- **No hay notificación automática a la persona.** El paso de notificar lo registra la Junta; el aviso lo envía quien corresponda.
- **Recurso.** Lo registra la Junta en nombre de la persona. No hay canal propio para que la persona recurra.
