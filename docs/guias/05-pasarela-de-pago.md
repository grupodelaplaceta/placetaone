# 05 · Pasarela de pago para webs de bancos

Permite que la web de tu banco (o de cualquier comercio de tu entidad) cobre con una ventana emergente de Placeta, con el logo de tu banco y un código de verificación que llega por tu propio canal.

## Flujo completo

1. **Tu backend crea el pago** (`POST /api/v1/bk/checkouts`, permiso `checkout:crear`). Indicas el DIP del pagador, su IBAN, el IBAN de destino, el importe y el concepto. El origen de tu web debe estar aprobado (guía 04).
2. **Placeta te envía el código por webhook** (evento `checkout.codigo`), con el código de 6 dígitos. Tu banco lo entrega al cliente por su canal (app, SMS, notificación). **No lo muestres en la web del comercio ni lo registres en logs.**
3. **Tu web abre la ventana** con `PlacetaCheckout.abrir({ url })`. La URL la devuelve el paso 1. Debe llamarse desde un clic del usuario, porque los navegadores bloquean ventanas que no vienen de un clic.
4. **El usuario escribe el código.** La ventana muestra el logo, los colores y el nombre de tu banco, el comercio, el importe y el concepto. Tiene tres intentos y caduca a los 15 minutos (configurable entre 3 y 30).
5. **Placeta hace la transferencia** y avisa a tu web con `postMessage` (`onPagado`). Además, te envía el evento `checkout.pagado` por webhook. **Confía en el webhook para registrar el pago** y usa el mensaje solo para actualizar la pantalla.

## Paso 1: crear el pago (servidor)

```ts
// app/api/pagos/route.ts  (tu backend)
import { placeta } from "@/lib/placeta";

export async function POST(req: Request) {
  const { pedido, dip, ibanPagador, importe } = await req.json();
  const pago = await placeta.crearCheckout({
    origen: "https://app.tubanco.es",            // aprobado para tu cliente
    client_ref: `pedido-${pedido.id}`,           // tu referencia (única por cliente)
    dip,
    iban_pagador: ibanPagador,
    iban_destino: "PZ-0002-0100",                // cuenta del comercio
    importe,
    concepto: `Pedido ${pedido.id}`,
    minutos: 15,
  });
  return Response.json({ url: pago.url, id: pago.id });
}
```

## Paso 2: recibir el código y el resultado (webhooks)

Configura un webhook en el panel con la URL de tu backend. Eventos que recibes:

| Evento | Cuándo | Qué hacer |
|---|---|---|
| `checkout.codigo` | Al crear el pago | Enviar `payload.codigo` al cliente por tu canal. Nunca mostrarlo en la web del comercio. |
| `checkout.pagado` | Pago confirmado | Marcar el pedido como pagado con `payload.client_ref` y `payload.transaccion`. |
| `checkout.cancelado` | El usuario cancela | Liberar el pedido. |

Verifica siempre la firma de cada webhook con el secreto de tu webhook antes de actuar.

## Paso 3: abrir la ventana (web)

```html
<script src="https://placetaone.vercel.app/placeta-checkout.js"></script>
<button id="pagar">Pagar 42,00 Pz</button>
<script>
  document.getElementById("pagar").addEventListener("click", async () => {
    const r = await fetch("/api/pagos", { method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ pedido: { id: 1001 }, dip: "12345678Z", ibanPagador: "PZ-0001-0002", importe: 42 }) });
    const { url } = await r.json();
    PlacetaCheckout.abrir({
      url,
      onPagado: (r) => { mostrarOk("Pago realizado: " + r.transaccion); },
      onError: (r) => { mostrarError("Pago no completado: " + r.estado); },
    });
  });
</script>
```

El script solo acepta mensajes del origen de Placeta. La ventana solo envía mensajes al origen que registró el banco.

## Estados del pago

| Estado | Significado |
|---|---|
| `pendiente` | Esperando el código |
| `pagado` | Transferencia realizada |
| `fallido` | Tres códigos incorrectos |
| `cancelado` | El usuario lo canceló |
| `caducado` | Pasó el tiempo de validez |

Puedes consultar cualquier pago con `GET /api/v1/bk/checkouts/{id}`. La respuesta nunca incluye el código.

## Seguridad

- El token de la URL tiene 256 bits de entropía y solo se guarda su hash. Quien no tenga la URL no puede ver ni pagar.
- El código se guarda solo como hash. Tres intentos fallidos cancelan el pago.
- Un pago solo puede pagarse una vez: la transferencia lleva como clave el identificador del pago.
- El pagador debe tener permiso de escritura sobre la cuenta (titular o cotitular).
- Los importes van de 0,01 a 50.000 Pz por pago.

## Qué no cubre esta versión

- No hay pago recurrente desde la pasarela: para cobros periódicos usa las suscripciones del personal.
- La web del comercio no ve los datos de la cuenta del pagador, solo el resultado del pago.
