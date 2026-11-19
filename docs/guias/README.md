# Guías de integración · Placeta One para entidades bancarias

Estas guías explican cómo construir la web o la app de tu entidad usando Placeta One como motor bancario.

| Guía | Para quién | Qué resuelve |
|---|---|---|
| [01 · Backend del banco](01-backend-del-banco.md) | Tu equipo de backend | Crear sesiones, vincular clientes, buscar por DIP, gestionar orígenes |
| [02 · Web](02-web.md) | Tu equipo de web | Patrón BFF (recomendado) y llamada directa con CORS |
| [03 · App móvil](03-app-movil.md) | Tu equipo de app | Flujo de login, pagos, notificaciones y almacenamiento seguro |
| [04 · Operación y producción](04-operacion-y-produccion.md) | Operaciones y seguridad | Errores, reintentos, idempotencia, pruebas, datos personales y salida a producción |

Además tienes:

- `sdk/`: cliente TypeScript. `placeta-usuario.ts` para web y app; `placeta-servidor.ts` solo para el backend.
- `docs/openapi.json`: especificación completa de los endpoints.
- `docs/postman/placeta-one.postman_collection.json`: colección lista para importar en Postman.
- `docs/API_REFERENCIA.md` y `docs/API_BANCOS.md`: referencia completa y guía de seguridad.

## La decisión que más importa: ¿quién habla con Placeta?

Hay dos formas de conectar tu web o app con Placeta. Elige una antes de empezar.

**Patrón BFF (recomendado).** Tu web o app solo habla con **tu propio backend**. Ese backend tiene la sesión de Placeta del usuario y la llama en su nombre. El navegador no recibe nunca un token de Placeta, así que CORS no se necesita.

**Llamada directa.** La web o la app llaman a Placeta con el token del usuario. Hace falta CORS aprobado para el origen de tu web (ver guía 04), y el token vive en memoria del navegador.

Las apps móviles nativas no están sujetas a CORS, pero deben tratar el token como una credencial y guardarlo en el almacenamiento seguro del dispositivo, o usar también el patrón BFF.

**Nunca** pongas la clave `x-api-key` ni el secreto de firma en una web o app. Placeta las rechaza desde navegadores, y aunque no lo hiciera, cualquiera podría copiarlas.
