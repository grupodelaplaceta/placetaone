# Empresas: ficha completa

## Qué es cada cosa
- **Empresa:** identificador fiscal, titulares, cuentas de empresa, pasarela y contrato. Se da de alta en la pantalla «Empresas» o con `POST /api/v1/bk/empresas`.
- **Entidad institucional:** organigrama, puestos, presupuestos, gastos y nóminas. Tiene su propio CIP y se gestiona en la pantalla «Institucional».
- **Vínculo:** una empresa tiene como máximo una entidad, y una entidad no puede estar en dos empresas.

## Cómo se administra
1. Dar de alta la empresa con su titular inicial y sus cuentas de empresa.
2. Vincular la entidad institucional (CIP). Lo pide un titular activo de la empresa.
3. Ver la ficha: organigrama, presupuesto por departamento y nóminas.

## Presupuesto por departamento
- **Asignado:** presupuesto anual de la unidad para el ejercicio en curso.
- **Pagado:** gastos de la unidad en estado pagado.
- **Comprometido:** gastos propuestos o aprobados, todavía no pagados.
- **Disponible:** asignado − pagado − comprometido. Aparece en rojo si es negativo.

## Nóminas
Las nóminas pagadas se agrupan por mes a partir del gasto que genera cada pago. Solo cuentan las nóminas cuyo gasto pertenece a la entidad vinculada.

## Límites conocidos
- Las retribuciones individuales no se muestran en la ficha, por privacidad. Se consultan en la pantalla institucional.
- La ficha muestra el ejercicio en curso. Para otros ejercicios hay que usar la pantalla institucional.

## Estado
Migración 0045: escrita y comprobada estáticamente. **No ejecutada en PostgreSQL.**
