# Placeta One
1. Supabase: crea un proyecto **staging**, ejecuta `supabase/migrations/0001_plone27_core.sql`.
2. Crea un usuario en Auth y da de alta su rol: `insert into plone27_staff(user_id,role) values('<uuid>','admin');`
3. Crea cuentas/bancos de prueba (incluye cuenta `system` con `allow_negative=true` para ingresos iniciales).
4. Vercel: importa el repo, define las 3 variables de `.env.example` (la service role solo en servidor) y despliega.
5. Ejecuta las migraciones 0001, 0002 y 0003 en orden. Crea entidades con `POST /api/rpc/plone27_open_bank`, actívalas (requiere `approved_by`) y cuentas con `plone27_open_account`.
6. Credenciales para una entidad: `POST /api/admin/clients` → usa `x-api-key` en `/api/v1/transfers` (POST) y `/api/v1/accounts/PZ-0027-0148` (GET).
7. Migraciones 0001–0004 + `supabase/tests/acceptance.sql` verificadas en PostgreSQL 16 (con roles/auth simulados). Contrato público: `docs/openapi.yaml`.
8. Migraciones 0001–0005. `CRON_SECRET` en Vercel para `/api/cron/webhooks` (cron diario; en plan Pro puedes cambiarlo a cada minuto en `vercel.json`). Panel: `/admin`. CI: `.github/workflows/ci.yml`.
9. Consola `/admin/console`, avisos `/api/cron/alerts`, pruebas `supabase/tests/{concurrency,restore}.sh`, despliegue por entornos en `docs/ENTORNOS.md`.
