# 03 · App móvil (iOS y Android)

Las apps nativas no están sujetas a CORS, pero el token de sesión es una credencial. Tienes dos opciones y la primera es la recomendada.

## Opción recomendada: la app habla con tu backend

Igual que en la guía 02, la app solo conoce tu backend y tu sesión (una cookie o un token propio de tu banco). Tu backend guarda el token de Placeta. Ventajas: la app no maneja credenciales de Placeta, y puedes revocar el acceso de un dispositivo desde tu lado.

```ts
// Cliente de tu app (React Native / Expo, ejemplo)
const API_BANCO = "https://api.tubanco.es";

export async function cuentas(tokenDeTuBanco: string) {
  const r = await fetch(`${API_BANCO}/banca/cuentas`, {
    headers: { authorization: `Bearer ${tokenDeTuBanco}` },
  });
  if (r.status === 401) throw new Error("SESION_CADUCADA");
  if (!r.ok) throw new Error(`Error ${r.status}`);
  return r.json();
}
```

Guarda tu token de sesión en el almacén seguro del dispositivo (Keychain en iOS, Keystore en Android; en Expo, `expo-secure-store`).

## Opción directa: la app habla con Placeta

Si necesitas la app sin backend intermedio, la app recibe un token de Placeta de tu backend tras el login y lo usa con el SDK:

```ts
import { PlacetaUsuario } from "./sdk/placeta-usuario";

const cliente = new PlacetaUsuario("https://api.placeta.example", tokenPlaceta);
const previsiones = await cliente.previsiones("2026-11-01", "2026-11-30");
```

Reglas:

- El token se guarda **solo** en el almacén seguro, no en `AsyncStorage` ni en ficheros.
- Caduca en 15 minutos: tu backend te debe dar uno nuevo. No intentes guardar un token para siempre.
- Al cerrar sesión, llama a `cerrarSesion()` y borra el token del dispositivo.
- Si el usuario cambia de contraseña o reporta un dispositivo perdido, cierra sus sesiones desde `cerrarOtrasSesiones()`, o desde tu backend.

## Notificaciones

La API entrega la bandeja de notificaciones (ingresos y cargos). El aviso en el móvil lo envía **tu** servicio de push (APNs y FCM), no Placeta:

1. Tu app registra el token de push del dispositivo en tu backend.
2. Tu backend consulta `notificaciones({ soloNuevas: true })` periódicamente o al recibir un evento de tu sistema.
3. Por cada notificación nueva envía un push y, al abrir la app, marca como leídas las que ha mostrado (`marcarLeidas(ids)`).

No muestres importes ni IBAN completos en la pantalla de bloqueo.

## Flujo de pago en móvil

Igual que en la guía 02: buscar destinatario, confirmar, enviar con una clave de idempotencia generada una vez por intento. Con una diferencia: en móvil un reintento automático al volver la conexión es habitual, así que **guarda la clave en el estado de la pantalla** para que sobreviva a ese reintento.

## Pruebas en dispositivo

- Prueba con red lenta y con el modo avión durante un pago: el pago no debe duplicarse.
- Prueba con el token caducado: la app debe volver al login sin perder el borrador de la transferencia.
- Prueba la rotación de pantalla y el paso a segundo plano durante una petición.
