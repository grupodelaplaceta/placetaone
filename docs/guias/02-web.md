# 02 · Web

## Recomendado: patrón BFF

Tu web habla solo con tu backend, en el mismo dominio. Tu backend tiene el token de Placeta y reenvía las peticiones.

Ventajas: sin CORS, el token nunca llega al navegador, y puedes aplicar tus propias reglas (límites, registro, detección de fraude) antes de llamar a Placeta.

### Backend: ruta que reenvía a Placeta

```ts
// app/api/banca/[...ruta]/route.ts  (Next.js, ejemplo)
import { cookies } from "next/headers";
import { PlacetaUsuario } from "../../../../sdk/placeta-usuario";

export async function GET(req: Request, { params }: { params: Promise<{ ruta: string[] }> }) {
  const sesion = await sesionBancoDesdeCookie();                 // tu lógica
  if (!sesion) return Response.json({ error: "No autenticado" }, { status: 401 });
  const token = await tokenVigente(sesion.clienteId);            // guía 01, flujo 2
  const cliente = new PlacetaUsuario(process.env.PLACETA_BASE!, token);
  const { ruta } = await params;
  const [recurso, ...resto] = ruta;
  switch (recurso) {
    case "cuentas": return Response.json(await cliente.cuentas());
    case "previsiones": {
      const u = new URL(req.url);
      return Response.json(await cliente.previsiones(u.searchParams.get("desde")!, u.searchParams.get("hasta")!));
    }
    default: return Response.json({ error: "No encontrado" }, { status: 404 });
  }
}
```

Añade un `POST` similar para las acciones que escriben (transferir, programar, reclamar RBU). **Reenvía siempre la `Idempotency-Key` que genera el navegador** (ver abajo).

### Frontend: llamar a tu propio backend

```tsx
// components/Cuentas.tsx
"use client";
import { useEffect, useState } from "react";

export function Cuentas() {
  const [cuentas, setCuentas] = useState<any[] | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    fetch("/api/banca/cuentas", { credentials: "same-origin" })   // mismo dominio: sin CORS
      .then(async (r) => { if (!r.ok) throw new Error(`Error ${r.status}`); return r.json(); })
      .then(setCuentas)
      .catch((e) => setError(e.message));
  }, []);
  if (error) return <p role="alert">No se pueden cargar tus cuentas. {error}</p>;
  if (!cuentas) return <p role="status">Cargando…</p>;
  return <ul>{cuentas.map((c) => <li key={c.iban}>{c.nombre} · {c.iban} · {c.disponible.toFixed(2)} Pz</li>)}</ul>;
}
```

## Alternativa: llamada directa desde el navegador

Solo si no puedes tener backend intermedio. Requisitos:

1. Tu origen aprobado para tu cliente (`/api/v1/bk/origenes`, guía 04).
2. El token de Placeta **en memoria**, nunca en `localStorage` ni en cookies accesibles por JavaScript.
3. Renovación desde tu backend, que te entrega un token nuevo antes de que caduque.

```ts
import { PlacetaUsuario } from "./sdk/placeta-usuario";

const cliente = new PlacetaUsuario("https://api.placeta.example", tokenEnMemoria);
const cuentas = await cliente.cuentas();
```

## Flujo de transferencia (con confirmación)

El flujo correcto tiene cuatro pasos. Cada uno hace una cosa, y el dinero solo se mueve en el último.

1. **Destinatario:** el usuario escribe un IBAN. Llama a `buscarIban` y muestra el titular abreviado (`Ma***`) para que confirme.
2. **Importe y concepto:** validación en el cliente (importe > 0, dentro del disponible).
3. **Confirmación:** resumen completo. El botón «Confirmar» genera la clave de idempotencia **una sola vez** para esta acción.
4. **Envío:** `transferir(payload, claveIdem)`. Si la red falla, reintenta **con la misma clave**. Si el usuario hace otra transferencia, genera una clave nueva.

```tsx
import { nuevaClaveIdempotencia, PlacetaError } from "./sdk/placeta-core";

const [clave] = useState(() => nuevaClaveIdempotencia());   // una por intento de pago
async function confirmar() {
  try {
    const r = await cliente.transferir({ desde_iban, hacia_iban, importe, concepto }, clave);
    mostrarOk(`Transferencia enviada (${r.transaccion})`);
  } catch (e) {
    if (e instanceof PlacetaError && e.status === 422) mostrarError(e.mensaje);     // p. ej. fondos insuficientes
    else mostrarError("No hemos podido confirmar el pago. Comprueba tus movimientos antes de reintentar.");
  }
}
```

No muestres «pago realizado» hasta recibir `201`. Si hay un error de red, consulta los movimientos antes de ofrecer reintentar.

## Accesibilidad y estados

- Cada pantalla tiene estado de carga, vacío y error con reintento.
- Importes con dos decimales y la unidad (Pz), y fechas en formato local.
- Botones de acción deshabilitados mientras se envía una petición, para evitar doble envío.
