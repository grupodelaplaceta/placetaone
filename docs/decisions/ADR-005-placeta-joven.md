# ADR-005: Placeta Joven como tipo de cuenta propio, con circulación controlada por la base de datos

- Estado: propuesto. Firma del responsable: pendiente. No ejecutado en PostgreSQL.

## Decisiones
1. **Tipo de cuenta `joven`**, distinto de `junior`. Las reglas (circulación, IVA) no son las de las cuentas junior.
2. **Circulación en la base de datos.** Un disparador diferido sobre el libro mayor revisa cada transacción que toca una cuenta Joven al confirmarla. Ninguna ruta puede saltársela.
3. **Contrapartes permitidas:** otras cuentas Joven, cuentas `system` (administración) y comercios Joven (empresas marcadas por la Junta).
4. **IVA desglosado como ajuste sensible.** `joven_iva_pct` (12 % por defecto) exige doble firma. La base y el IVA se calculan en la misma operación, con dos transferencias.
5. **Idempotencia por clave.** Repetir una compra o recarga con la misma clave no duplica el cobro.

## Riesgos y decisiones pendientes
- La regla no se ha probado todavía en PostgreSQL. Es el punto a verificar primero.
- Todas las cuentas `system` son destino válido. Si la Junta quiere un conjunto cerrado, hay que indicarlo.
- Falta decidir si Placeta Joven se fusiona con `junior` o convive con él.
- Falta la verificación de edad y el tutor legal, si la plataforma va a admitir menores.

## Actualización (migración 0068)
- **Banco propietario:** todas las cuentas Joven pertenecen a Banco de La Placeta. Solo ese banco crea, compra, recarga y congela.
- **Solo lectura para los demás bancos** (`joven:leer`). Decisión de privacidad abierta: ver `docs/PLACETA_JOVEN.md`, sección 12.
- **Congelación:** estado por cuenta. Bloquea cualquier movimiento en la base de datos, no solo en la API.
- **Marca obligatoria:** ningún movimiento sobre una cuenta Joven sale sin la marca de Placeta Joven.
