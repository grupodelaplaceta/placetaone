# Idempotencia de los movimientos (resultado de la revisión)

- `plone27_transfer` → `plone27_post`: **idempotente.** Una clave repetida con los mismos datos devuelve la transacción original. Con datos distintos, falla con «Idempotency-Key reutilizada con datos distintos». No se duplica ningún movimiento.
- `plone27_debt_pay` (cobro de deudas): **no lo era.** La transferencia era idempotente, pero la deuda sumaba el pago otra vez en cada repetición. **Corregido en la migración 0043:** la repetición devuelve la transacción original sin tocar la deuda. Los datos distintos con la misma clave fallan.
- Las reclamaciones y devoluciones se controlan por estado (solo se resuelven una vez) y por la clave `disp:<id>`.

Pruebas que lo demuestran: `verificacion/pruebas_db.sql`, pruebas 1 a 4.
