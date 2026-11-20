# ADR-004: las empresas convocan subvenciones y bonos

- Estado: aprobado por la Junta según la instrucción del 2026-11-19. Firma del responsable: pendiente.

## Decisiones
1. **La empresa es la convocante.** Su titular abre la convocatoria desde la API de banca (con `dip_actor`). Cada convocatoria crea su programa con una **cuenta de fondos de la propia empresa**, y reutiliza reserva, caducidad, reversión y reautorización.
2. **Destino.** `todos`: cualquier beneficiario de la entidad. `empresa`: solo la empresa indicada.
3. **Sin autoconcesión.** Una empresa no puede conceder a sus propias cuentas. Es la regla que impide sacar dinero de la propia cuenta.
4. **Bonos con caducidad.** Un bono exige fecha de caducidad, por convocatoria o explícita.
5. **Permisos.** Abrir, conceder, revertir y cerrar exigen permiso de presupuestar o ejecutar en la entidad de la convocatoria. La Junta puede operar sin restricción.
6. **Reserva por concesión.** Cada concesión reserva su importe; la convocatoria limita el presupuesto total.

## Riesgos y decisiones pendientes
- `todos` admite cualquier beneficiario **de la misma entidad**, no de otras entidades. Ampliarlo a otras entidades exige un acuerdo entre ellas.
- La autoconcesión se bloquea solo para cuentas **de la misma empresa**. Empresas vinculadas entre sí (grupos) no están cubiertas: decidir si se bloquean también.
- La convocatoria no reserva su importe completo al abrirse; cada concesión reserva lo suyo. Si se quiere reservar todo de entrada, es un cambio posterior.
- Las empresas operan por el titular a través de la API de banca. Todavía no tienen una pantalla propia.
- Verificación: SQL estático y verificación del repositorio. No ejecutado en PostgreSQL.
