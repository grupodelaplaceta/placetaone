# Restricciones de uso: subvenciones y bonos RBU (propuesta, pendiente de decisión)

## Situación actual (verificada en el código)
- **Subvenciones:** se paga a posteriori, contra gastos justificados (`plone27_justify` y `plone27_reimburse`). No hay control del tipo de gasto ni del comercio.
- **Bonos RBU:** se pagan por adelantado en una tarjeta prepago (lotes con caducidad). Se gastan en cualquier comercio.
- Las cuentas no tienen categoría de comercio.

## Opciones
1. **RBU: restricción por categoría de comercio en el momento del cargo.** Cada cuenta de comercio recibe una categoría. Cada lote de RBU declara las categorías permitidas, y la autorización de la tarjeta prepago solo usa lotes válidos para ese comercio. Requiere migración, campo de categoría y pantalla para asignarla.
2. **Subvenciones: restricción en la justificación.** La justificación lleva un tipo de gasto obligatorio y el personal lo valida antes de pagar. No bloquea el gasto, pero evita pagos fuera del destino.
3. **Restricción por tipo de operación** (transferencia interbancaria, pago de comercio, cargo de tarjeta). Se aplica en el mismo punto que la opción 1, pero se decide por operación y no por comercio.

## Recomendación
- RBU: opción 1 (se paga por adelantado, así que la restricción debe estar en el cargo).
- Subvenciones: opción 2 (se paga a posteriori, así que la restricción debe estar en la justificación).

## Decisiones que necesito
1. ¿Qué categorías de comercio quieres? (propuesta: alimentación, salud, educación, transporte, vivienda, ocio y otros).
2. ¿Quién asigna la categoría a cada comercio: Placeta o el propio banco?
3. ¿Aceptas que las subvenciones se controlen en la justificación y no en el gasto?
