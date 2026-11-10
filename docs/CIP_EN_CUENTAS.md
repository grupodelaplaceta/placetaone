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

## Crear la entidad de una empresa (0050)
- Desde la banca: `POST /api/v1/bk/empresas/{id}/entidad/crear`. La entidad recibe un CIP nuevo y el identificador de la empresa pasa a ser ese CIP.
- Desde el panel (Junta): en la ficha de la empresa, «Crear entidad institucional».
- Vincular un CIP que no existe en el banco devuelve un error explícito: la entidad debe existir y estar activa.

## Empresa = entidad (0051)
- Si una cuenta de la empresa ya es una entidad activa de su banco, la empresa queda vinculada a esa entidad automáticamente.
- Crear la entidad reutiliza la entidad que ya exista en esa cuenta. Solo falla si esa entidad ya está vinculada a otra empresa (el mensaje indica cuál).

## Empresa = entidad institucional (0052)
La empresa es su entidad institucional. Al añadir su primera cuenta de empresa se crea automáticamente la entidad (o se reutiliza la que ya tenga esa cuenta), y el identificador de la empresa pasa a ser su CIP. No hay que vincular nada a mano; los endpoints de vinculación se mantienen solo por compatibilidad.

## Añadir cuentas y forzar la entidad (0053)
- Añadir una cuenta: `POST /api/v1/bk/empresas/{id}/cuentas` (o «Añadir cuenta» en el panel). Da acceso a los titulares según su rol y asegura la entidad.
- Crear o reutilizar la entidad: `POST /api/v1/bk/empresas/{id}/asegurar-entidad` (o «Crear entidad institucional» en el panel).
- La creación automática al insertar cuentas no bloquea el alta: si no puede crear la entidad, deja constancia en el registro de auditoría y el botón la crea.

## Automático sin cron (0054)
- Al añadir una cuenta a una empresa, su entidad institucional se crea sola (y reutiliza la que ya tenga esa cuenta).
- No hay cron para esto: la entidad se crea en el momento en que se añade la cuenta. Si quedara alguna pendiente, el botón «Crear entidad institucional» de la ficha la crea.
- Si la creación falla, el motivo queda en la auditoría y se muestra en la ficha («Último error automático»).
- El DIP del titular es opcional al añadir cuentas o al crear la entidad.
