# Normativa del motor fiscal certificado de Placeta One

**Estado:** propuesta para aprobación por la Junta del Grupo de La Placeta.
**Fecha de propuesta:** 29 de octubre de 2026.
**Ámbito:** cálculo, emisión, cobro y certificación de los tributos internos (Arts. T1–T99 y Anexos I–III).
**Relación con la normativa vigente:** esta propuesta añade los Arts. T100 a T111 y aplica la prioridad de los artículos T sobre los Arts. 4.x de la Normativa Institucional Unificada v5.0 en los puntos que se indican en el Art. T100.

> Las decisiones marcadas como **[D]** no pueden resolverse en código: las toma la Junta. El Anexo A las lista con la recomendación técnica.

---

## Art. T100 · Prioridad de los artículos T

1. Los artículos T prevalecen sobre cualquier artículo 4.x que regule la misma materia.
2. Se aplican las siguientes sustituciones expresas:

| Materia | Artículo 4.x | Regla que prevalece | Efecto |
|---|---|---|---|
| Mora por retraso en tributos | 4.3: interés de demora por segundo | **Art. T57** (recargos por tramos de días) | Se deja sin efecto el devengo por segundo sobre recibos. |
| Tasa de transferencia | 4.3: la fija el Departamento Económico cada periodo | **Arts. T3.2 y T93**: solo la Junta modifica tipos | La tasa se propone por el Departamento Económico y la aprueba la Junta. El tope del 12 % se mantiene. |
| Gestión del IVA | 4.4: la gestiona el Departamento Económico | **Arts. T6 y T8**: la gestión es de la Administración; el Departamento Económico informa | La recaudación se ingresa en la Cuenta de Reserva, sin cambios. |
| Salario mínimo | 4.7.2: 150 Pz semanales (= 30 × RBU) | **Instrucción de la Junta**: 160 Pz semanales | El bruto mínimo pasa a 160 Pz semanales. Deja de cumplirse la equivalencia «30 × RBU» (RBU = 5 Pz): se aprueba expresamente. |
| Pago de impuestos de operaciones Junior | 4.x y T19–T21: obligado Placeta Junior; Capitalia no obligada por el soporte | **Art. T105** | Capitalia paga, según la decisión [D1]. |

3. Los Arts. 4.5 (cotizaciones), 4.6 (RBU) y 4.7.1 y 4.7.3 (definición y revisión del SMI) no tienen equivalente en los Arts. T y se mantienen.

## Art. T101 · Recargos por retraso (Art. T57, operativo)

1. Sobre la cantidad pendiente de un recibo vencido se aplica el tipo del tramo que corresponde a los días transcurridos desde el vencimiento:
   - hasta 7 días: 1 %;
   - de 8 a 30 días: 3 %;
   - de 31 a 90 días: 5 %;
   - de 91 a 180 días: 10 %;
   - más de 180 días: 15 %.
2. El recargo **no es acumulable entre tramos** [D2]: en cada momento el recargo total es el del tramo vigente sobre lo pendiente. Cuando el tramo sube, se emite solo la diferencia.
3. Si lo pendiente baja (pago parcial), no se devuelve nada al contribuyente.
4. Cada recargo es una deuda automática con certificado (Art. T102). Se cobra con el autocobro de deudas.
5. El recargo es independiente de la sanción (Art. T57.2).

## Art. T102 · Certificación de cálculos

1. Todo recibo fiscal, toda regularización y todo recargo generan un **certificado** en el momento de su creación.
2. El certificado contiene: referencia de la norma y de la versión aplicada, huella de la versión (Art. T104), base, desglose por tramos, importe, obligado, operación de origen y huella de encadenamiento.
3. Los certificados son de solo añadir. No se modifican ni se borran.
4. Una versión publicada es inmutable. Sus tramos también (no se pueden insertar, modificar ni borrar tramos de una versión publicada).
5. La entidad debe poder mostrar el certificado de cada recibo a su titular.

## Art. T103 · Alcance de la certificación

1. El certificado acredita que **el importe es el que resulta de aplicar la versión publicada a la base registrada**, y que la versión, la base y el importe no han cambiado desde su emisión.
2. El certificado **no acredita que la base sea correcta**. La base procede de dos fuentes, cada una con su trazabilidad:
   - **Operaciones registradas** en el libro (ventas, nóminas): la base es el importe de la operación.
   - **Bases declaradas** (Art. T108): la base la declara una persona y la aprueba otra.
3. La veracidad completa de un importe requiere, por tanto, que la base sea veraz. Esto depende de los registros del libro y de las declaraciones, que deben estar sujetos a control (Art. T109).

## Art. T104 · Huella de la versión y cadena de certificados

1. **Huella de la versión:** SHA-256 del texto JSON canónico formado por método, tasa, mínimo, máximo, fechas de vigencia, ámbito y tramos (desde, hasta, tipo), ordenados por «desde». La huella se fija al publicar.
2. **Cadena:** cada certificado incluye el hash del anterior. El hash de un certificado es el SHA-256 (en hexadecimal) del texto canónico del Anexo B.
3. **Verificación:** el sistema recalcula cada hash y cada importe con la norma vigente. Un resultado distinto de cero en cualquiera de estas comprobaciones es una incidencia.
4. **Verificación externa:** cualquier tercero puede comprobar un certificado si conoce su texto canónico (Anexo B). Esto acredita integridad, no la base (Art. T103).

## Art. T105 · Pagador de impuestos de operaciones Junior **[D1]**

1. El **obligado** de un impuesto derivado de una operación Junior es el usuario Junior, identificado en el recibo (Art. T18.2 y T20.3).
2. El **pagador** es Capitalia Bank cuando la Junta active este artículo; cuando no, Placeta Junior (Art. T19). El pagador sale de su cuenta principal, que es propia de la entidad.
3. El pago de Capitalia no la convierte en obligada tributaria (Art. T21.3), salvo que la Junta apruebe expresamente lo contrario [D1].
4. El sistema registra, para cada recibo Junior: operación de origen, usuario Junior, pagador, impuesto, base, cuota, periodo y entidad cobradora (Art. T20.3).
5. Esta activación se hace por la configuración `capitalia_asume_impuestos_junior`, que es sensible y exige aprobación de otra persona.

## Art. T106 · Operaciones sujetas e IVA automático

1. Es operación sujeta al IVA toda venta de bienes o servicios dentro del sistema, por su precio base (Art. T26 y 4.4).
2. El comprador paga el precio base más el IVA, desglosado en la transacción. El vendedor es el obligado a liquidar el IVA, salvo en operaciones Junior, donde se aplica el Art. T105.
3. Están exentas las operaciones que la Junta reconozca como tales (Art. T27.3), registradas como exención con fundamento legal.
4. El IVA se liquida en la Cuenta de Reserva del Grupo.

## Art. T107 · Actividades económicas e IAEP

1. Una actividad se registra con su categoría (microactividad, pequeña, mediana, grande o especial) antes de operar (Art. T43.1).
2. La cuota del IAEP se emite cada mes de forma automática. La microactividad tiene cuota cero y no genera recibo (Art. T43.2).
3. Un cambio de circunstancias obliga a reclasificar la actividad (Art. T42.3). La reclasificación tiene efecto desde el mes siguiente.

## Art. T108 · Bases declaradas

1. Para los impuestos cuya base no se registra automáticamente (IRM, IBA, IGF, IPE, ITP), el obligado presenta una declaración con la base y el periodo. El sistema calcula el importe con la norma vigente y lo certifica.
2. La declaración la aprueba una persona distinta del declarante. Sin esa aprobación no se emite el recibo.
3. La Junta debe definir la base de cada impuesto antes de su entrada en vigor [D3]: qué son los «movimientos» del IRM, qué ingresos y gastos son computables en el IBA, cómo se valora el patrimonio en el IGF y el IPE, y cuál es el valor reconocido en el ITP.

## Art. T109 · Controles adicionales

1. **Publicación con dos firmas:** toda versión la publica un aprobador distinto de su autor.
2. **Tipos sensibles:** todo cambio de un tipo o tramo de un ajuste sensible exige aprobación de otra persona.
3. **Separación de funciones:** quien declara una base no la aprueba; quien gestiona el IVA no es quien aprueba la norma.
4. **Informe diario de certificación:** cada día se recalcula la cadena y los importes. Si el estado no es «OK», se abre una incidencia de tipo `certificacion`.
5. **Auditoría:** cada publicación, declaración, cobro y cambio de ajuste deja registro en el libro de auditoría, que es de solo añadir.

## Art. T110 · Rectificación de recibos **[D4]**

1. Un importe emitido no se modifica. Si hay que corregirlo, se emite un **recibo rectificativo** que referencia al original, y el original queda rectificado.
2. Esto sustituye a la nota de crédito que modifica el importe (migración 0009; prueba de aceptación, línea 85). La sustitución requiere cambiar esa prueba.

## Art. T111 · Entrada en vigor y no retroactividad

1. Esta normativa entra en vigor el 1 de enero de 2027, junto con la Sección de Tributos [D5].
2. Los certificados se emiten desde la entrada en vigor. Los recibos anteriores se registran como «sin certificado de origen», sin reconstruirlos.
3. Ninguna modificación desfavorable tiene efecto retroactivo (Art. T94).

---

## Anexo A · Decisiones que toma la Junta

| Ref. | Decisión | Opciones | Recomendación técnica |
|---|---|---|---|
| D1 | Capitalia paga los impuestos Junior; ¿asume también la obligación? | (a) Solo paga, obligado el usuario Junior. (b) Paga y asume la obligación (exige reescribir T19, T21.3 y Anexo III). | (a) Es lo que el sistema implementa sin contradecir T21.3. |
| D2 | Recargo T57: tramo vigente o acumulable | (a) Tramo vigente, no acumulable. (b) Acumulable entre tramos. | (a), que es como se lee el texto. |
| D3 | Base de IRM, IBA, IGF, IPE, ITP | Definir cada una (Art. T108.3) | Antes de publicar esos tributos. |
| D4 | Rectificación de recibos | (a) Recibo rectificativo (Art. T110). (b) Mantener nota de crédito. | (a). Obliga a cambiar la prueba de aceptación. |
| D5 | Fecha de entrada en vigor | 1 de enero de 2027 o posterior | 1 de enero de 2027. |
| D6 | Tasa de transferencia | Quién propone y quién aprueba | Propone el Departamento Económico; aprueba la Junta (T100). |
| D7 | Salario mínimo: 160 Pz semanales | Confirmar y revisar la equivalencia con la RBU | Aprobar y revisar la RBU en la próxima revisión. |
| D8 | Cotización: tipo del tramo sobre todo el bruto | Tipo marginal o tipo del tramo sobre todo el bruto | Confirmar: el sistema aplica el segundo. |
| D9 | IRP sobre el bruto o sobre el bruto menos cotizaciones | Dos opciones | Confirmar: el sistema aplica el bruto. |
| D10 | Día de pago de la nómina | Día 28 es un supuesto | Confirmar. |

## Anexo B · Texto canónico y huella del certificado

El texto que se hashea, en este orden y separado por `|`:

```
hash_anterior | tipo | sujeto | version | huella_norma | base | importe | calculo_json
```

- `hash_anterior`: hash del certificado anterior en la cadena, o `GENESIS` si es el primero.
- `tipo`: `recibo`, `regularizacion` o `recargo`.
- `sujeto`: identificador del recibo o de la deuda.
- `version`: identificador de la versión de la norma, o `-`.
- `huella_norma`: huella de la versión (Art. T104.1), o `-`.
- `base` e `importe`: con dos decimales (por ejemplo, `1000.00`).
- `calculo_json`: JSON con el desglose por tramos, el obligado y la operación.

El hash es el SHA-256 de ese texto en UTF-8, en hexadecimal.

Ejemplo de respuesta de la API (`GET /api/v1/accounts/{iban}/receipts/{ref}/certificate`):

```json
{
  "recibo": "PL27-REC-2027-000123",
  "norma": "IVA",
  "version": 1,
  "huella_norma": "9f2c…",
  "base": "1000.00",
  "importe": "120.00",
  "calculo": { "tramos": [{ "metodo": "percent", "tasa": "12.0000", "base": "1000" }], "cuenta": "…" },
  "seq": 4821,
  "hash": "a7e1…",
  "hash_anterior": "3b0c…",
  "emitido": "2027-01-15T09:00:00Z"
}
```

## Anexo C · Cobertura del motor por impuesto

| Impuesto | Hecho imponible | Base | Estado |
|---|---|---|---|
| IVA | Venta sujeta (`plone27_sale`) | Precio base registrado | Automático |
| IAEP | Actividad registrada, cuota mensual | Fija por categoría | Automático |
| IRP | Nómina | Bruto mensual | Automático en nómina. Otros ingresos: declarado |
| Cotizaciones | Nómina | Bruto mensual | Automático |
| T57 (recargo) | Recibo vencido | Pendiente | Automático |
| IRM | Movimientos (sin definir, D3) | Declarada | Declarado (Art. T108) |
| IBA | Beneficio (sin definir, D3) | Declarada | Declarado |
| IGF | Patrimonio (sin definir, D3) | Declarada | Declarado |
| IPE | Patrimonio empresarial (sin definir, D3) | Declarada | Declarado |
| ITP | Transmisión patrimonial (sin definir, D3) | Declarada | Declarado |
| Tasa de transferencia | Transferencia | Importe de la operación | Automático, con tope del 12 % |

## Anexo D · Aprobación

| Órgano | Qué aprueba | Firma |
|---|---|---|
| Junta del Grupo de La Placeta | Esta normativa y las decisiones D1 a D10 | ☐ |
| Departamento de Tributos (Art. T7) | Fórmulas, tramos y verificación de la huella | ☐ |
| Departamento Económico (Art. T8) | Tasa de transferencia (propuesta) y tipos de demora | ☐ |
| Administración (Art. T6) | Gestión del IVA y permisos de emisión | ☐ |
| Capitalia Bank | Condiciones del pago de impuestos Junior (D1) | ☐ |

---

## Segunda ronda · cambios aprobados por instrucción (29 de octubre de 2026)

Estos cambios sustituyen a lo anterior donde se contradigan.

- **Art. T105 (modificado) · Capitalia paga en nombre del usuario Junior.** Capitalia paga todos los impuestos de las operaciones Junior, mensuales y de cualquier otra clase. El obligado sigue siendo el usuario Junior, y así queda registrado en cada recibo. Esto resuelve la decisión D1 en la opción (a). Queda en la configuración `capitalia_asume_impuestos_junior` (activa), que es sensible y se registra en auditoría.
- **Art. T100 (modificado) · SMI de 160 Pz al mes.** El salario mínimo para jornada completa es de 160 Pz al mes. Se valida sobre el bruto mensual. Sustituye la lectura semanal de la ronda anterior (decisión D7 confirmada por la Junta).
- **Art. T110 (modificado) · Los certificados no se modifican.** Si un recibo cambia (por ejemplo, con una nota de crédito), el sistema emite un certificado nuevo de tipo «rectificación» que apunta al anterior. El anterior queda intacto. Un recibo siempre tiene su historial completo de certificados.
- **Art. T112 · IVA configurado en Placeta One.** El IVA se configura en Placeta One para todo el sistema, no por entidad. Las ventas se registran con su base y su IVA. Las operaciones sin registro se detectan y se regularizan (Art. T115).
- **Art. T113 · Cuentas institucionales que operan con Junior.** Solo las cuentas institucionales que la Junta marque pueden operar con cuentas Junior, además de las propias cuentas Junior entre sí. Ninguna otra cuenta personal, compartida o de empresa puede operar con ellas. Cada marca queda registrada con su motivo.
- **Art. T114 · IBAN de tributos y origen de la RBU.** Tributos tiene su propio IBAN. Cada impuesto tiene un destino configurable, que debe ser una cuenta institucional. El bono de la RBU sale de una cuenta de origen con IBAN, también configurable; por defecto es la Reserva. Los cambios afectan a los cobros posteriores y quedan registrados.
- **Art. T115 · Transferencias comerciales sin IVA.** Se considera cobro comercial sin IVA la transferencia que entra en una cuenta de empresa sin venta registrada. Se consideran señales a revisar el patrón comercial en cuentas personales (muchos pagadores distintos en un periodo) y el fraccionamiento (varias transferencias pequeñas al mismo comercio en un día que suman más del umbral). El sistema solo detecta. La regularización exige una propuesta y la aprobación de otra persona, y emite el recibo de IVA a cargo del receptor. Las sanciones (Arts. T67 y T69) las decide el procedimiento sancionador, nunca el escaneo.

### Umbrales configurables (no fijados por la norma; propuesta)

| Ajuste | Valor propuesto | Qué controla |
|---|---|---|
| `iva_umbral_fraccionamiento` | 500 Pz | Suma diaria a partir de la cual varias transferencias pequeñas son fraccionamiento |
| `iva_patron_pagadores` | 5 | Pagadores distintos en la ventana para revisar una cuenta personal |
| `iva_ventana_patron_dias` | 30 | Ventana del patrón comercial |
| `iva_criterio` | exclusivo | El importe detectado es la base; el IVA se calcula encima |

### Decisiones pendientes que quedan abiertas

- **D1 resuelta** (opción a): obligado = usuario Junior; pagador = Capitalia.
- **D4 modificada**: se mantiene la nota de crédito, pero cada cambio genera un certificado nuevo (Art. T110).
- **D7 confirmada**: SMI de 160 Pz al mes.
- **D11 nueva**: umbrales de detección (tabla anterior).
- **D12 nueva**: si las cuentas de sistema (Reserva, Tributos) pueden operar con cuentas Junior sin estar marcadas. Hoy quedan fuera de la restricción Junior, como antes. La norma debe decidirlo.
