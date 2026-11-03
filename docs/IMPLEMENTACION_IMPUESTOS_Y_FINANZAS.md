# Impuestos, pagos a plazos, suscripciones y nóminas · Implementación

Migración `0011_plone27_finanzas.sql` + seed `supabase/seeds/0011_seed_norma_tributos_2027.sql`.
Ejemplos de web y app en la sección 5. Todo lo que no está en la norma aparece como **supuesto** o **pendiente**.

> **Estado: sin ejecutar.** El entorno donde se preparó no tiene PostgreSQL ni acceso a red. Las cifras de los
> ejemplos están comprobadas con una réplica en Python de la lógica de tramos; el SQL no se ha ejecutado.
> Antes de nada: CI (que ejecuta `supabase/migrations/*.sql` con `ON_ERROR_STOP`) y luego staging.

## 1. Qué había y qué falta

| Área | Antes (0001–0010) | Después (0011) |
|---|---|---|
| Fechas de cálculo | Programadas con `run_at` y recurrencia sin fin ni nº de cuotas. Membresía de cuenta Junior (solo Junior). | Calendario de cuotas con fecha de cálculo (`plone27_plans`, `plone27_plan_items`) y suscripciones generales. |
| Interés | Tipo mensual fijo por producto, abonado a la cuenta del producto. | Tipo automático de la entidad (`interes_anual_pct`). Se abona en la **cuenta principal** de la entidad. |
| Mora | Recargo único escalonado (Art. T57), desactivado por defecto. | Interés de demora **por segundo** (Art. 4.3) que crea deuda automática. Conmutable con T57. |
| Cuenta de la entidad | No existía. | `main_account` (principal) y `tax_account` (impuestos). Cada entidad elige de dónde paga; por defecto la principal. |
| Cobros | Manuales. | Autocobro diario de recibos, cuotas, suscripciones y deudas. Solo de cuentas cobrables. |
| Nóminas | Lotes manuales, sin cotizaciones, IRP ni SMI. | Contratos validados contra el SMI, cotizaciones (Art. 4.5), IRP sobre el bruto y nómina diaria. |
| RBU | No existía. | Bono semanal reclamable a mano, caduca al final de la semana y va a una cartera no embargable. |
| Tributos | Motor de tramos sin datos. | Seed con todos los tipos y tramos. Cada versión entra en borrador hasta que la publica un aprobador. |

## 2. Decisiones y conflictos a confirmar

**Conflictos entre fuentes** (no los he resuelto por mi cuenta):

1. **Mora.** El Art. T57 fija recargos del 1 % al 15 % según días de retraso. El Art. 4.3 fija interés de demora por segundo tras una semana. Están implementados los dos, y `demora_habilitada` decide cuál aplica. Por defecto ambos están inactivos.
2. **Tasas de transferencia.** El Art. 4.3 dice que el Departamento Económico fija la tasa cada periodo. Los Arts. T3 y T93 dicen que solo la Junta modifica tipos. Dejo el tope del 12 % como restricción dura (trigger). Quién fija la tasa queda por decidir.
3. **Gestión del IVA.** El Art. 4.4 lo asigna al Departamento Económico; el Art. T6 a la Administración. No cambia el cálculo, solo los permisos.

**Lo que la norma no fija** (lo dejo en 0 o como supuesto, no lo invento):

4. **Tipos de interés.** La norma no da ningún porcentaje de cuotas ni de demora. `interes_anual_pct` y `demora_anual_pct` quedan en 0 (sin intereses) hasta que se aprueben. El tope de cuotas es 60 % anual (5 % mensual, tope central que ya existía).
5. **Vigencia.** 1 de enero de 2027, según el título («de cara al 2027»).
6. **Cotizaciones.** Solo aparecen en el Art. 4.5, no en el PDF. Las modelo como tramo sobre **todo** el bruto (la tabla no dice si es marginal).
7. **IRP en nómina.** Se aplica sobre el bruto mensual. El ejemplo del Art. T36 (600 Pz → 5 Pz) no aclara si es antes o después de cotizaciones.
8. **SMI.** Se comprueba `bruto mensual × 12 / 52 ≥ 150 Pz`, lo que equivale a un bruto mínimo de **650 Pz mensuales**. Solo se admite jornada completa; la parcial no tiene norma.
9. **Día de nómina.** Supuesto: día 28 (`dia_nomina`).
10. **Menores excluidos de la RBU.** Implementado como «tiene ficha Junior».
11. **RBU «no transferible».** Implementado como «solo el titular puede reclamar». El dinero ya cobrado puede gastarse; no lo bloqueo.
12. **Interés «sale de la cuenta principal».** Lo interpreto así: el capital de las cuotas sale de la principal y capital más interés vuelven a ella; los intereses del crédito interno también se abonan allí. Si quieres que la principal **pague** el interés (subvención), es cambiar el signo de una línea.
13. **Impuestos de operaciones Junior.** El Art. T19 dice que Placeta Junior asume los tributos «cuando lo establezca la normativa específica», y esa normativa no existe en el documento. Creo la cuenta «Placeta Junior · pagos asumidos» en el seed y dejo a la app decidir qué emitir contra ella.

## 3. Puesta en marcha (en este orden)

1. CI corre la migración 0011 (si falla, ver el error antes de tocar nada).
2. Staging: ejecutar el seed `0011_seed_norma_tributos_2027.sql`. Sus autocomprobaciones paran el seed si el motor no reproduce las cifras de la norma.
3. Configurar la entidad: `plone27_bank_set_accounts(bank, principal, impuestos, actor)`. Sin cuenta principal no se pueden hacer cuotas ni emitir impuestos de entidad.
4. Publicar cada versión de tributos con `plone27_tax_publish(version, aprobador, actor)`. El aprobador tiene que ser distinto del autor.
5. Fijar tipos: `plone27_setting_propose('interes_anual_pct', '12'::jsonb, bank, motivo, actor)` (sensible: lo aprueba otra persona con `plone27_setting_approve`). `demora_anual_pct` se fija a nivel central con el mismo mecanismo.
6. El cron `/api/cron/finanzas` se ejecuta a las 04:00 cada día. La mora se devenga por segundos aunque el cron sea diario: la cantidad no depende de la frecuencia, solo cuándo se liquida. Con el plan Pro de Vercel se puede subir la frecuencia.

## 4. Cómo se calcula (con cifras comprobadas)

- **IVA**: base 1.000 Pz → 120 Pz (12 %).
- **IGF** (tramos): patrimonio 900.000 Pz → 106.400 Pz. Cada tramo solo tributa su parte.
- **IRP** (tramos): ingreso mensual 600 Pz → 5 Pz. Con 1.500 Pz → 25 + 50 = 75 Pz.
- **IBA** (tramos): beneficio mensual 8.000 Pz → 435 Pz.
- **ITP** (tramos): transmisión de 75.000 Pz → 4.200 Pz.
- **Nómina de 1.500 Pz brutos**: cotización trabajador 7,5 % = 112,50; cotización empresa 7,5 % = 112,50; IRP = 75.
  La empresa debita 1.612,50 Pz; el trabajador recibe 1.312,50 Pz; la Reserva ingresa 225 Pz; el IRP va a su recaudadora. El asiento cuadra.
- **Cuota**: 12.000 Pz en 12 meses al 12 % anual (ejemplo, no aprobado). Cuota constante de 1.066,19 Pz. El primer mes: interés 120,00 y capital 946,19. Interés mensual = tipo anual / 12, sobre saldo vivo.
- **Mora por segundo**: 1.000 Pz pendientes, 10 % anual, 1 día → 1000 × 0,10 × 86.400 / 31.536.000 = **0,27 Pz**.
- **SMI**: bruto de 650 Pz mensuales es el mínimo (650 × 12 / 52 = 150 Pz semanales).
- **RBU**: 5 Pz semanales por titular con cuenta personal. Caduca el lunes siguiente.

## 5. Ejemplos de implementación en web y app

Las apps hablan con el banco por la API con `x-api-key`, igual que hoy. Estos ejemplos siguen el patrón existente de `src/app/api/v1/`. Las rutas nuevas son **ejemplos**; no están incluidas en el zip. Para usarlas hay que añadir sus ámbitos en `src/lib/scopes.ts`.

### 5.1 Desglose de una operación con IVA visible (Art. 4.4)

El IVA tiene que verse desglosado en toda transacción comercial interna. Este componente recibe base e IVA ya calculados por el servidor y no recalcula nada en el cliente.

```tsx
// components/DesgloseIVA.tsx
type Desglose = { base: number; iva: number; total: number; tipo: number };

export function DesgloseIVA({ d }: { d: Desglose }) {
  const pz = (n: number) => `${n.toLocaleString("es-ES", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} Pz`;
  return (
    <dl className="desglose">
      <dt>Base</dt><dd>{pz(d.base)}</dd>
      <dt>IVA ({d.tipo} %)</dt><dd>{pz(d.iva)}</dd>
      <dt><strong>Total</strong></dt><dd><strong>{pz(d.total)}</strong></dd>
    </dl>
  );
}
```

### 5.2 Recibos fiscales del titular (endpoint existente)

`GET /api/v1/accounts/{iban}/receipts` ya devuelve los recibos. Con el autocobro, la mayoría se paga sola en su fecha; la app solo muestra el estado y avisa si un recibo sigue pendiente porque faltan fondos.

```tsx
// app/(cuenta)/impuestos/page.tsx (cliente)
type Recibo = { ref: string; amount: number; paid_amount: number; status: "issued" | "partial" | "paid" | "rectified"; due_date: string };

export async function listarRecibos(iban: string, apiKey: string): Promise<Recibo[]> {
  const r = await fetch(`${process.env.NEXT_PUBLIC_BANK_API}/api/v1/accounts/${iban}/receipts`, { headers: { "x-api-key": apiKey } });
  if (!r.ok) throw new Error("No se pueden cargar los recibos");
  return r.json();
}

export function estadoRecibo(r: Recibo): string {
  const pendiente = r.amount - r.paid_amount;
  if (r.status === "paid") return "Pagado";
  if (r.status === "partial") return `Pendiente ${pendiente.toFixed(2)} Pz (vence ${r.due_date})`;
  return `Se cobrará de tu cuenta el ${r.due_date}`;
}
```

### 5.3 Pagos a plazos: simulación en pantalla y alta en el servidor

La vista previa del cliente es **solo informativa**: el servidor decide el calendario. La cuota se calcula con la misma fórmula que `plone27_plan_schedule`.

```ts
// lib/simulador-cuotas.ts  (solo vista previa)
export function cuotaMensual(capital: number, tipoAnualPct: number, meses: number): number {
  const m = tipoAnualPct / 1200;
  if (m === 0) return Math.round((capital / meses) * 100) / 100;
  return Math.round((capital * m) / (1 - Math.pow(1 + m, -meses)) * 100) / 100;
}
// cuotaMensual(12000, 12, 12) → 1066.19
```

Alta de un plan. Cuando el titular confirma, la app llama a la API y el servidor crea el plan, genera el calendario y desembolsa el capital desde la cuenta principal de la entidad:

```ts
// src/app/api/v1/accounts/[iban]/plans/route.ts  (ejemplo)
import { clientFrom, ownAccount } from "@/lib/apikey";

export async function POST(req: Request, { params }: { params: Promise<{ iban: string }> }) {
  const a = await clientFrom(req, "plans:write");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const key = req.headers.get("idempotency-key");
  if (!key) return Response.json({ error: "Falta Idempotency-Key" }, { status: 400 });
  const id = await ownAccount(a.db, a.c.bank_id, (await params).iban);
  if (!id) return Response.json({ error: "No encontrada" }, { status: 404 });

  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_plan_create", {
    p_key: `${a.c.id}:${key}`,
    p_kind: b?.kind,                                   // "installment" | "subscription"
    p_debtor: id,
    p_beneficiary: b?.beneficiary_account_id,          // debe ser de la misma entidad (validar antes)
    p_principal: Number(b?.principal),
    p_installments: b?.installments ?? null,
    p_start: b?.start_date,                            // fecha de cálculo
    p_approved_by: a.c.id,                             // aprobación registrada por la entidad (ver nota)
    p_actor: a.c.id,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ plan: data });
}
```

Nota: `p_approved_by` con el id del cliente API deja constancia de que la entidad lo aprobó. Si tu política exige una persona del personal, sustitúyelo por el id de quien aprueba.

### 5.4 Suscripción mensual (sin cuotas)

Misma llamada con `kind: "subscription"`, `principal` = importe por mes y sin `installments`. El cobro es automático el día de `start_date` y después cada mes con ese mismo día (`plone27_add_months` ajusta el día 31 al último del mes). No genera intereses.

### 5.5 Reclamar la RBU (la reclamación la hace el titular)

```ts
// src/app/api/v1/rbu/[id]/claim/route.ts  (ejemplo)
import { clientFrom } from "@/lib/apikey";

export async function POST(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const a = await clientFrom(req, "rbu:write");
  if (a.err) return Response.json({ error: "Denegado" }, { status: a.err });
  const key = req.headers.get("idempotency-key");
  if (!key) return Response.json({ error: "Falta Idempotency-Key" }, { status: 400 });
  const b = await req.json().catch(() => null);
  const { data, error } = await a.db.rpc("plone27_rbu_claim", {
    p_bonus: (await params).id, p_user: b?.user_id, p_key: `${a.c.id}:${key}`,
  });
  if (error) return Response.json({ error: error.message }, { status: 422 });
  return Response.json({ transaction: data });
}
```

```tsx
// Botón en la app: el bono es «available» hasta que lo reclamas o caduca
export function BotonRBU({ bono, reclamar }: { bono: { id: string; amount: number; status: string; expires_on: string }; reclamar: (id: string) => Promise<void> }) {
  if (bono.status !== "available") return <p>Bono {bono.status === "claimed" ? "reclamado" : "caducado"}</p>;
  return <button onClick={() => reclamar(bono.id)}>Reclamar {bono.amount} Pz (caduca el {bono.expires_on})</button>;
}
```

### 5.6 Tasa de transferencia visible en la pantalla de envío

La tasa nunca supera el 12 % (Art. 4.3) y el trigger lo impide también en base de datos. La app muestra la tasa antes de confirmar y el coste total:

```tsx
export function ResumenTransferencia({ importe, tasaPct, quienPaga }: { importe: number; tasaPct: number; quienPaga: "user" | "bank" | "both" | "exempt" }) {
  const tasa = Math.min(importe * tasaPct / 100, importe);
  const cobra = quienPaga === "user" ? tasa : quienPaga === "both" ? tasa / 2 : 0;
  return <p>Tasa de transferencia: {cobra.toFixed(2)} Pz · Total: {(importe + cobra).toFixed(2)} Pz</p>;
}
```

## 6. Qué se ejecuta cada día (`plone27_finanzas_daily`)

1. Caducar RBU sin reclamar. 2. Emitir la RBU de la semana. 3. Programadas vencidas. 4. Cuotas de productos. 5. Interés de crédito interno (a la cuenta principal). 6. Membresías Junior. 7. Nóminas. 8. Cuotas y suscripciones vencidas. 9. Mora por segundo (crea deuda). 10. Recargos T57, si están activos. 11. Autocobro de recibos. 12. Autocobro de deudas.

Cada paso va en su propio bloque: si uno falla, queda en `plone27_incidents` con `kind = finanzas_diario` y el resto sigue. Los pasos son idempotentes, así que se pueden relanzar sin duplicar.

## 7. Pendiente y no verificado

- Ejecutar la migración y el seed en staging. No se ha hecho.
- Pruebas de aceptación para 0011 (cuotas que cuadran, mora, nómina que cuadra, RBU caducada, no cobro de cartera RBU). Están por escribir.
- Pantallas del panel para la cuenta principal, el publicado de versiones y el calendario de cuotas (hoy solo se opera por API y SQL).
- Conflictos 1 a 3 y supuestos 4 a 13: decisión de la Junta, no de código.

## 8. Actualización 0012 (prioridad de los artículos T)

Esta sección sustituye a las partes anteriores que quedan contradichas:

- **Mora:** el interés de demora por segundo (Art. 4.3) queda desactivado (`demora_habilitada = false`). Rige el recargo T57 por tramos de días, con su propio tramo de recargo y un certificado por cada cambio de tramo (`plone27_t57_run`).
- **Salario mínimo:** 160 Pz semanales (antes 150). El bruto mensual mínimo equivalente es 693,34 Pz (`160 × 52 / 12`), no 650.
- **Pagador Junior:** `plone27_set_junior_payer` configura Capitalia. `plone27_junior_tax_payer` elige el pagador según `capitalia_asume_impuestos_junior`. Esa configuración está inactiva hasta que la Junta apruebe D1 (véase la normativa).
- **Certificación:** cada recibo se certifica al crearse. `plone27_certification_report()` recalcula la cadena y los importes. `plone27_receipt_certificate(recibo)` devuelve el certificado para la app. El cron diario abre una incidencia si el estado no es OK.
- **IVA de ventas:** `plone27_sale(clave, comprador, vendedor, base, actor)` cobra base más IVA y emite el recibo de IVA.
- **Bases declaradas:** `plone27_tax_declare(...)` exige aprobación de otra persona.
- **IAEP:** `plone27_activity_register` y `plone27_iaep_monthly` (cada día comprueba si toca emitir).

**Pendiente, no resuelto en código:** la nota de crédito de 0009 modifica el importe de un recibo emitido. El informe lo marca como «importe alterado tras emisión». Lo correcto es el recibo rectificativo (Art. T110, decisión D4).
