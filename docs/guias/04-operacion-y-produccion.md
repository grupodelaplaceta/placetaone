# 04 · Operación y producción

## CORS: qué es y qué no es

CORS decide qué página del navegador puede leer las respuestas de la API. Sus reglas en Placeta:

- Solo se aceptan orígenes **aprobados** para tu cliente (`https://dominio[:puerto]`, sin ruta ni comodines).
- Un origen aprobado vale solo para tu cliente.
- Las apps nativas no envían cabeceras de origen y no están afectadas por CORS.
- CORS no protege nada por sí solo: la protección real son el token de sesión y las comprobaciones de cuenta.

Para solicitar un origen: `POST /api/v1/bk/origenes` desde tu backend. Queda pendiente hasta que Placeta lo apruebe. Para `http://localhost` y dominios de prueba, pide el entorno `pruebas`.

## Errores y cómo reaccionar

| Código | Causa habitual | Qué hacer |
|---|---|---|
| 400 | Dato fuera de formato | Valida antes de enviar; muestra el campo |
| 401 | Token caducado o revocado; firma incorrecta | Renueva la sesión y reintenta una vez |
| 403 | Permiso no concedido; clave usada desde navegador | Revisa permisos y arquitectura |
| 404 | No existe **o no es tuyo** | Muestra «no encontrado»; no reveles más |
| 409 | Nonce repetido en el servidor | Genera otro nonce y reintenta |
| 422 | Operación no posible (fondos, destino no válido) | Muestra el mensaje al usuario |
| 429 | Demasiadas peticiones | Espera con retroceso exponencial (el SDK ya lo hace para lecturas) |
| 5xx | Error del servidor | Reintenta con retroceso; en escrituras, **con la misma clave** |

## Idempotencia: la regla más importante del dinero

- Genera la `Idempotency-Key` **una vez por acción del usuario**, no por petición.
- Si una petición falla por red o por 5xx, reintenta **con la misma clave**. Placeta devuelve el resultado original y no duplica el pago.
- Si el usuario hace otro pago, genera una clave nueva.
- Si no sabes si el pago se hizo, **consulta los movimientos antes de reintentar**.

## Límites y rendimiento

- Límite por cliente (`rate_limit`, por defecto 60 peticiones por minuto). Si tu app crece, pide más al equipo de Placeta.
- Movimientos paginados (máximo 100 por página). Usa `siguiente` para cargar más, no pidas todo de golpe.
- Las previsiones admiten 366 días como máximo; para un calendario anual, pide dos rangos.

## Pruebas antes de publicar

1. **Pruebas de aislamiento.** Con dos usuarios reales de tu entidad, ejecuta `scripts/aislamiento.mjs`. Todas las comprobaciones deben estar en OK.
2. **Pruebas de flujo.** Login, ver cuentas, extracto, transferencia con confirmación, programar, cancelar, reclamar RBU, cerrar sesión.
3. **Pruebas de fallo.** Caída de red a mitad de un pago; token caducado; 429; 5xx simulado.
4. **Pruebas de seguridad.** Intenta leer una cuenta ajena cambiando el IBAN en la URL; intenta usar la clave desde el navegador; intenta un origen no aprobado.
5. **Colección de Postman.** Importa `docs/postman/placeta-one.postman_collection.json` y recorre los endpoints con el entorno de pruebas.

## Datos personales

- El DIP es dato personal. Envíalo solo cuando tengas base legal para tratarlo.
- No lo registres en tus logs ni en tu navegador. Si necesitas trazabilidad, usa el hash que Placeta registra en su auditoría.
- Define cuánto tiempo guardas los datos de tus clientes en tu propio sistema.
- Los nonces y las sesiones caducadas los borra Placeta cada día; no dependas de ellos para auditoría.

## Salida a producción: lista de verificación

- [ ] Clave y secreto de firma en el gestor de secretos de tu infraestructura, no en el código.
- [ ] Orígenes de producción aprobados; ningún origen de pruebas en producción.
- [ ] Permisos mínimos por sesión (`me:read` y `me:transfer` salvo que necesites más).
- [ ] Renovación de sesión probada, incluido el caso de caducidad en mitad de uso.
- [ ] Flujos de pago probados con fallos de red.
- [ ] Monitorización de errores 401, 403, 422 y 5xx. Un pico de 401 suele ser una caducidad mal gestionada; un pico de 403 suele ser un permiso que falta.
- [ ] Plan de rotación de clave y secreto probado en pruebas.
- [ ] Equipo de guardia que sepa a quién avisar en Placeta.

## Rotación de credenciales

Si sospechas que la clave o el secreto de firma se han filtrado:

1. Pide a Placeta un cliente nuevo.
2. Cambia tu backend al cliente nuevo y verifica que funciona.
3. Pide la desactivación del cliente anterior.

La firma depende del secreto, así que la clave y el secreto se rotan juntos.
