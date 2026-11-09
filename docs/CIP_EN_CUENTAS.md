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

## Cuenta sin CIP: cómo solucionarlo desde la banca
Si la cuenta devuelve `cip: null`, la empresa no tiene entidad institucional vinculada. Hay dos vías, las dos por API:

1. **Crear la entidad sobre una cuenta de la empresa** (la más habitual):
   `POST /api/v1/bk/empresas/{id}/entidad/crear` con `{ "dip_actor": "…", "iban": "PZ-0000-0007" }`.
   La cuenta pasa a tener CIP (`cip_origen: cuenta`).
2. **Vincular una entidad que ya existe:** `POST /api/v1/bk/empresas/{id}/entidad` con `{ "cip": "CIP-…", "dip_actor": "…" }`.

Después, crea las unidades del organigrama (`POST /api/v1/bk/organigrama`, `accion: unidad`). Sin unidades, la ficha de la empresa no tendrá organigrama ni presupuesto por departamento.

## Estado
Migración 0047: escrita y comprobada estáticamente. **No ejecutada en PostgreSQL.**

## Identificador de empresa = CIP
En la plataforma no existe NIF: el identificador de una empresa es el CIP de su entidad institucional. Cuando el identificador de una empresa coincide con el CIP de una entidad activa de su mismo banco, la empresa queda vinculada automáticamente (al darla de alta, al corregir sus datos y, para las existentes, en la migración 0049).
