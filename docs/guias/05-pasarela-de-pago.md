# 05 · Pasarela de pago

El pago lo confirma el **banco de quien paga**, no Placeta. El cliente puede pagar con una cuenta o con una tarjeta de cualquier banco.

## Flujo

1. **Tu backend crea el pago** (`POST /api/v1/bk/checkouts`, permiso `checkout:crear`). Indicas el DIP del pagador y su cuenta (`iban_pagador`) o su tarjeta (`tarjeta_ref`), y la cuenta del comercio (`iban_destino`).
2. **Placeta avisa al banco del pagador** con el evento `checkout.confirmacion_requerida`.
3. **El banco del pagador autentica a su cliente** en su propia app o banca online. Placeta no pide ni valida ningún código.
4. **El banco aprueba o rechaza**: `POST /api/v1/bk/pagos/{id}/resolucion` con `decision: "aprobado"` o `"rechazado"`, y el DIP del cliente que autoriza. Al aprobar, Placeta ejecuta el cobro y, si corresponde, la comisión.
5. **Tu web recibe el resultado** por el evento `checkout.pagado` o `checkout.rechazado`, y la ventana de pago avisa a tu web por `postMessage`.

## Quién paga la comisión

Solo se aplica si el destino está en otro banco.

- **El propietario de la pasarela** fija la tarifa de cada banco y decide quién cobra la comisión.
- **El banco del pagador** decide, para cuentas y para tarjetas por separado, si la comisión la paga el cliente o la absorbe el banco (`PUT /api/v1/bk/comisiones`).

## Qué no hace Placeta

- No pide ni valida códigos de verificación. Eso lo hace el banco del pagador.
- No guarda contraseñas ni credenciales de otros bancos.
- No deja que un banco resuelva pagos de clientes de otro banco.

## Seguridad

- El token de la ventana tiene 256 bits de entropía y solo se guarda su hash.
- Un pago solo se puede resolver una vez, y solo por el banco de la cuenta o tarjeta del pagador.
- El cobro se hace con la clave de idempotencia del pago, así que un reintento no cobra dos veces.
- Los importes van de 0,01 a 50.000 Pz por pago.
