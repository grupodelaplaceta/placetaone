# Despliegue y puesta en producción

## 1. Antes de nada
- Confirma que tienes una **base de pruebas** separada de producción (proyecto de Supabase distinto).
- Ejecuta la comprobación previa: `python3 verificacion/preflight.py .` (con las variables de entorno del entorno que vas a desplegar).

## 2. Variables de entorno (Vercel → Settings → Environment Variables)
| Variable | Obligatoria | Notas |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | sí | URL https del proyecto de Supabase |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | sí | |
| `SUPABASE_SERVICE_ROLE_KEY` | sí | Solo en el servidor. Nunca en el navegador |
| `CRON_SECRET` | sí | Mínimo 24 caracteres. Vercel Cron lo envía como `Authorization: Bearer` |
| `WEBHOOK_KEY` | sí | Mínimo 24 caracteres. Cifra los secretos de webhook. **No cambiarla después**: invalida los secretos existentes |
| `PLACETA_PUBLIC_URL` | sí | URL pública de la aplicación (sin barra final) |
| `ALERT_WEBHOOK_URL` | recomendable | Avisos de incidencias |
| `REQUIRE_MFA` | sí | `true` en producción |
| `PLACETA_ENTORNO` | no | Solo `pruebas` en entornos de prueba (permite localhost en CORS) |

## 3. Base de datos
1. En la **base de pruebas**: abre el editor SQL de Supabase y ejecuta `plone27_setup_completo.sql` completo. Debe terminar con «aplicada correctamente». Si falla, **no sigas**: corrige y repite.
2. Ejecuta las pruebas de base de datos (desde un equipo con `psql`):
   ```
   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v cuenta_a='PZ-XXXX-XXXX' -v cuenta_b='PZ-YYYY-YYYY' -f verificacion/pruebas_db.sql
   ```
   Deben aparecer `OK 1` a `OK 6` y ningún `FALLO`. Las cuentas deben existir en la base de pruebas.
3. Prueba la subida de un logo: un PNG válido debe subirse; un archivo que no sea imagen, o con dimensiones fuera de rango, debe rechazarse.
4. Solo cuando todo lo anterior pase, ejecuta el **mismo** `plone27_setup_completo.sql` en producción. **No ejecutes nada en producción que no haya pasado antes en la base de pruebas.**

## 4. Aplicación
1. Despliega la aplicación en Vercel (el repositorio con `vercel.json`, que programa los crons de webhooks, alertas, finanzas y liquidación).
2. Comprueba que los crons aparecen en Vercel → Cron Jobs, y que cada uno responde 200 con `CRON_SECRET`.

## 5. Interruptores (todos empiezan apagados)
- **Liquidación interbancaria y tasas**: panel «Liquidación interbancaria». No los actives hasta haber pasado las pruebas de movimientos en la base de pruebas.
- **Secretos de webhook antiguos**: panel «Pasarela y webhooks» → «Desactivar los que tienen secreto en claro». Después, avisa a cada banco para que rote su secreto.

## 6. Comprobaciones después de desplegar
- Un pago de pasarela de prueba de extremo a extremo.
- Una transferencia de usuario de prueba y su registro en el panel.
- Una reclamación de prueba: abrir, rechazar, y volver a abrir si procede.
- La exportación de datos de un usuario de prueba.

## 7. Si algo sale mal
- Revierte la aplicación a la versión anterior en Vercel (Deployments → Promote).
- La base de datos no tiene una vuelta atrás automática. La instalación es idempotente, pero los datos creados con la versión nueva permanecen. **Por eso la prueba en la base de pruebas es obligatoria.**
