# ADR-003: subvenciones con fondos autorizados, caducidad y reversión de abonos

- Estado: aprobado por la Junta. Firma del responsable: pendiente.

## Decisiones
1. **Fondos autorizados.** Crear una subvención o bono reserva su importe en la cuenta del programa. Un abono consume la reserva; lo no usado se libera al caducar o revertir. Nadie puede conceder por encima del presupuesto del programa.
2. **Caducidad por convocatoria.** Cada convocatoria puede tener fecha de caducidad propia. Los bonos la exigen; una subvención la hereda si no se indica otra. Caducar libera la autorización sin pagar (proceso diario).
3. **Reversión.** El subvencionante puede revertir un abono concreto o la subvención completa. La reversión usa un asiento contrario; la justificación queda rechazada para que no se pague dos veces. Requiere permiso de ejecutar en la entidad o ser la Junta.
4. **Informe de justificación.** Resumen por subvención en JSON o PDF: concedido, aprobado, pagado, pendiente, justificaciones y abonos revertidos.
5. **Sin excepciones a la doble firma.** Ni el admin puede aprobar sus propios cambios de ajustes ni publicar versiones fiscales que redacta (revertido en la migración 0064).

## Riesgos conocidos
- Revertir un abono debita al beneficiario: si ya ha gastado ese dinero, la reversión falla con error explícito (no crea deuda automática).
- Un abono revertido deja la justificación rechazada: el beneficiario debe presentar una nueva con otra transacción.
- Verificación: SQL estático y verificación del repositorio. No ejecutado en PostgreSQL.

## Actualización (migración 0064)
- Revertir un abono sin saldo suficiente: lo disponible vuelve al programa y el resto queda como deuda del beneficiario frente al subvencionante.
- La deuda cobrada después no vuelve a autorizarse automáticamente: el programa la recupera sin reserva. Decidir si debe reautorizarse.
- Se retira la excepción de la Junta a la doble firma en ajustes y publicación fiscal.
