# Reclamaciones de deudas (decisiones aprobadas y flujo)

## Decisiones
- **Quién abre:** el titular de la cuenta deudora, con permiso de escritura en esa cuenta (API de usuario, `me:transfer`).
- **Qué se puede reclamar:** solo lo ya pagado, y como máximo el importe pagado.
- **Plazo para abrir:** 60 días desde el vencimiento de la deuda.
- **Efecto al abrir:** la deuda queda en disputa. No se cobra ni manualmente ni por autocobro hasta resolverla.
- **Quién resuelve:** personal con permiso de aprobador (panel «Reclamaciones»).
- **Plazo para resolver:** 30 días desde la apertura. Si se supera, la reclamación aparece como «plazo vencido». Nada se resuelve sola: la decisión siempre es humana.
- **De dónde sale la devolución:** de la cuenta del acreedor. Si no tiene saldo, la devolución no se ejecuta.
- **Devoluciones de más de 1.000 Pz:** las aprueban dos personas distintas. La primera aprobación queda registrada y la segunda la ejecuta.
- **Rechazar:** la deuda vuelve a poder cobrarse.

## Estado
- Migración 0042: escrita y comprobada estáticamente. **No ejecutada en PostgreSQL.**
- Probar: abrir una reclamación sobre una deuda pagada; comprobar que no se puede pagar ni autocobrar mientras esté abierta; devolver con dos aprobadores; rechazar; comprobar que una deuda con acreedor en otro banco registra la operación para la liquidación.
