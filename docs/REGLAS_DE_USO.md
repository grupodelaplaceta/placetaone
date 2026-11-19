# Reglas de uso: RBU, subvenciones y comercios

## Decisiones aprobadas
- **Tipos de cuenta de destino:** los que ya existen en la plataforma (personal, empresa, compartida, junior, sistema).
- **Comercios concretos:** una lista de cuentas de empresa por regla (convocatoria o bono).
- **Categorías:** las asigna Placeta a cada cuenta de comercio. Solo las cuentas de empresa pueden tener categoría.
- **Subvenciones:** el control se hace en la justificación. Se rechaza el gasto que no cumple la regla del programa.
- **RBU:** el control se hace en cada cargo de tarjeta prepago, antes de autorizarlo.
- **Convocatoria = programa de subvención o bono.**
- **Sin regla = sin restricción.** Es el comportamiento anterior, y no cambia nada para quien no tiene reglas.

## Cómo se combinan los filtros
Cada filtro configurado debe cumplirse a la vez. Un filtro vacío no restringe.
- `tipos`: el tipo de cuenta de destino debe estar en la lista.
- `comercios`: el destino debe estar en la lista de cuentas.
- `categorias`: el comercio debe tener una de las categorías (las cuentas sin categoría no cumplen).

Una regla nueva del mismo ámbito sustituye a la activa.

## Dónde se aplica
- **RBU:** disparador `trg_rbu_destino` sobre los cargos de tarjetas prepago. Si el comercio no cumple la regla RBU del banco, el cargo no se crea.
- **Subvenciones:** disparador `trg_justificacion_destino` sobre las justificaciones. Comprueba que el gasto sea un cargo de la cuenta beneficiaria y que su destino cumple la regla del programa. Se aplica también a justificaciones creadas desde el panel.

## Estado
- Migración 0044 y API de banco: escritas y comprobadas estáticamente. **No ejecutadas en PostgreSQL.**
- Error 42P13 corregido en la instalación completa: antes de crear nada se borran todas las variantes existentes de `plone27_checkout_create`.
- **Probar antes de producción:** crear una regla RBU con una categoría; pagar con una tarjeta prepago en un comercio que sí y en uno que no; justificar un gasto de un programa con regla y uno que no la cumple.
