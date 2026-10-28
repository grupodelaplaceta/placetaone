# Entornos y despliegue
| Entorno | Rama Git | Supabase | Vercel |
|---|---|---|---|
| Staging | `main` (Preview) | proyecto `placeta-one-staging` (datos de prueba) | variables en *Preview* |
| Producción | rama `production` | proyecto `placeta-one-prod` | variables en *Production* |

1. Crea **dos proyectos Supabase** y aplica `supabase/migrations/*.sql` en orden en cada uno (primero staging).
2. Antes de promocionar a producción: `supabase/tests/acceptance.sql` y `concurrency.sh` en staging; `restore.sh` con `SRC`=staging y `DST`=una base vacía.
3. Vercel → Settings → Environment Variables: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (solo servidor), `CRON_SECRET`, `ALERT_WEBHOOK_URL`. Distintas claves por entorno.
4. Haz el primer admin en SQL: `insert into plone27_staff(user_id,role) values('<uuid Auth>','admin');`. Desde ahí usa `/admin/console`.
5. Activa copias automáticas (PITR) en el proyecto de producción de Supabase.
6. Seguridad del personal: en Supabase → Authentication activa MFA (TOTP), contraseñas fuertes y límites de intentos; desactiva el registro público de usuarios.
7. Configuración: todo ajuste operativo vive en `/admin/settings` (global o por entidad, dentro de límites centrales; los sensibles exigen una segunda persona).
