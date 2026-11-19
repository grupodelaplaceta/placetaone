# Complementos de actividad y conceptos de nómina para NEXE (0058)

## Qué se puede hacer por API
1. **Catálogo de complementos** de la entidad: `GET/POST /api/v1/bk/empresas/{id}/complementos`.
2. **Asignar un complemento a un contrato** (la retribución de la persona): `POST /api/v1/bk/empresas/{id}/complementos/asignaciones`. Sin importe, se usa el importe base. No se puede asignar dos veces el mismo complemento activo al mismo contrato.
3. **Retirar** una asignación desde una fecha: `POST .../asignaciones/{asig}/retirar`.
4. **Conceptos del periodo para NEXE**: `GET /api/v1/bk/empresas/{id}/nomina/conceptos?periodo=AAAA-MM`. Una línea por retribución y por complemento vigente en el periodo, con el DIP de cada persona.

## Permisos
- Escribir (catálogo, asignar, retirar): permiso de **retribuir** en la entidad. La persona que actúa se indica con `dip_actor`. El titular de la empresa lo tiene desde el alta.
- Leer conceptos: scope `nominas:read`.

## Qué no hace (a propósito)
- **No emite nóminas.** Eso lo hace NEXE leyendo `conceptos`.
- **No cambia el motor de nóminas existente.** Las tareas (`tareas`) siguen su propio flujo de registro, validación y pago; no se incluyen en `conceptos`.
- **Los complementos variables** se asignan con su importe por periodo. El cálculo por actividad registrada (horas, tareas) queda para una fase posterior.

## Pendiente
- Conector con NEXE (fuera de este código).
- Decidir si las tareas validadas entran en `conceptos`.

## Estado
Migración 0058: escrita y comprobada estáticamente. **No ejecutada en PostgreSQL.**

## Emisión y pago para NEXE (0059)
- **Pagar la nómina del periodo:** `POST /api/v1/bk/nominas/periodos` (permiso `nominas:generar`). Paga el salario y **los complementos vigentes**. Es idempotente por persona, periodo y referencia: repetir no paga dos veces.
- **Confirmar qué se ha pagado:** `GET /api/v1/bk/empresas/{id}/nomina/recibos?periodo=AAAA-MM` (JSON por persona, con su transferencia).
- **Recibo en PDF:** `GET .../nomina/recibos?periodo=AAAA-MM&dip=DIP&formato=pdf`.
- Quien asigna un complemento o autoriza un salario no puede ejecutar la nómina.
- El PDF es un recibo de texto simple, sin logotipos ni formato legal. Si NEXE necesita un formato oficial, se define como plantilla más adelante.
