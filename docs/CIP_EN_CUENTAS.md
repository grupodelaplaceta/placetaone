# CIP de la entidad institucional en las cuentas

## Qué se informa
En `GET /api/v1/me/accounts` y en `GET /api/v1/bk/cuentas`, cada cuenta incluye:
- **`cip`:** el CIP de la entidad institucional, o `null` si la cuenta no pertenece a ninguna.
- **`cip_origen`:** de dónde sale el CIP.
  - `cuenta`: la cuenta es la cuenta de la propia entidad.
  - `empresa`: la cuenta pertenece a una empresa vinculada a la entidad (ver `docs/EMPRESAS.md`).
  - `null`: sin CIP.

## Qué debe hacer el banco
Nada, si consume la API de Placeta: la respuesta ya incluye los dos campos. Si mantiene una copia de las cuentas, debe leer `cip` y `cip_origen` de cada cuenta.

## Por qué una cuenta de empresa podía no tener CIP
La cuenta de empresa no es la cuenta de la entidad: el CIP está en la cuenta de la entidad. Por eso el CIP sale por el vínculo empresa → entidad. Si la empresa no tiene entidad vinculada, la cuenta no tiene CIP. Para solucionarlo, vincula la entidad (`POST /api/v1/bk/empresas/{id}/entidad`).

## Estado
Migración 0047: escrita y comprobada estáticamente. **No ejecutada en PostgreSQL.**
