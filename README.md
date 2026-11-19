# Placeta One

Sistema bancario interno del Grupo de La Placeta (Plan 2027): cuentas y tarjetas, pasarela de pago para cuentas de empresa e institucionales, API para las entidades (bancos), nóminas, presupuestos institucionales, subvenciones y finanzas automatizadas.

## Nivel DEVAI y estado
- **Nivel 2 (DEVAI)**, asumido porque no constaba; pendiente de confirmar.
- **Manual DEVAI: 2.0.** Auditoría vigente: [`docs/audits/2026-11-19-devai.md`](docs/audits/2026-11-19-devai.md). El proyecto **no está listo para publicación** (ver el informe).
- **Estado: activo, en desarrollo.** No publicado en producción.

## Tecnologías y versiones
- Next.js 15.1.9, React 19.0.1, TypeScript 5.7.2 (`strict`).
- Node.js 20 (`.nvmrc`).
- Supabase (PostgreSQL 16) con RLS.
- Vercel (despliegue y crons en `vercel.json`).
- GitHub Actions (`.github/workflows/ci.yml`).

## Instalación
```bash
nvm use            # usa la versión de .nvmrc (20)
npm install        # pasar a `npm ci` cuando exista package-lock.json (DEV-001 de la auditoría)
cp .env.example .env.local   # rellenar valores fuera del repositorio
```

## Comandos
| Comando | Qué hace |
|---|---|
| `npm run dev` | Servidor de desarrollo |
| `npm run build` | Build de producción |
| `npm run start` | Arranca el build |
| `npm run verificar` | Verificación completa: tipos, documentación de la API, SQL y coherencia de llamadas |
| `npx tsc --noEmit` | Comprobación de tipos (lo ejecuta el CI) |
| Lint | PENDIENTE: no existe script `lint` |
| Pruebas | PENDIENTE: no existe script `test` |

## Variables de entorno (solo nombres)
Las define `.env.example`. Ver el significado de cada una en `docs/ENTORNOS.md` y `docs/DESPLIEGUE.md`.

- Públicas (`NEXT_PUBLIC_*`): `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- Solo servidor: `SUPABASE_SERVICE_ROLE_KEY`, `CRON_SECRET`, `WEBHOOK_KEY`, `PLACETA_PUBLIC_URL`, `PLACETA_ENTORNO`, `REQUIRE_MFA`, `ALERT_WEBHOOK_URL`.

Nunca se usan variables `NEXT_PUBLIC_*` para secretos. Algunas variables aceptan nombres alternativos (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_PUBLISHABLE_KEY`).

## Base de datos
- `supabase/migrations/`: migraciones `0001` a `0059`, en orden.
- `supabase/setup/plone27_setup_completo.sql`: instalación completa en una sola transacción. Para bases nuevas.
- `supabase/setup/plone27_actualizacion_00NN.sql`: actualización de una migración concreta, para bases que ya tienen las anteriores.
- `supabase/tests/`: pruebas de aceptación, concurrencia y restauración. El CI ejecuta las migraciones en PostgreSQL 16.
- `verificacion/pruebas_db.sql`: pruebas de idempotencia y reglas de dinero. Ejecutar solo en una base de pruebas.

**Nunca ejecutar migraciones en producción sin probarlas antes en una base de pruebas.**

## Estructura
- `src/app/`: pantallas (panel de la Junta) y rutas de API (`src/app/api/`).
- `src/lib/`: autenticación, permisos, cifrado de secretos de webhook, PDF, operaciones de empresas.
- `sdk/`: SDK para integradores.
- `supabase/`: migraciones, instalación, pruebas y semillas.
- `verificacion/`: verificación previa al despliegue.
- `docs/`: documentación, inventario de API (`docs/API.md`), auditorías y guías.
- `public/`: scripts públicos (pasarela de pago).

## Integraciones
- Supabase (base de datos y almacenamiento de logos).
- Vercel (despliegue y cron diario de liquidación, finanzas, webhooks y alertas).
- Entidades bancarias: API con clave, firma HMAC y permisos por recurso (ver `docs/API_BANCA_Y_PANEL.md`).
- NEXE (nóminas): conceptos y recibos por periodo (ver `docs/NOMINA_NEXE.md`).

## Documentación
- Contrato de la API: `docs/openapi.json`. Inventario: `docs/API.md`.
- Referencia y guías: `docs/API_REFERENCIA.md`, `docs/guias/`, `docs/API_BANCA_Y_PANEL.md`.
- Despliegue y entornos: `docs/DESPLIEGUE.md`, `docs/ENTORNOS.md`.
- Seguridad: [`SECURITY.md`](SECURITY.md).
- Agentes y automatización: [`AGENTS.md`](AGENTS.md).
- Novedades: [`CHANGELOG.md`](CHANGELOG.md).

## Responsables técnicos y de seguridad
| Técnico | Identificación DIP | Rol |
|---|---|---|
| PENDIENTE | PENDIENTE | Responsable técnico |
| PENDIENTE | PENDIENTE | Responsable de seguridad |

Los responsables se completan con datos reales. No se han inventado nombres ni DIP.

## Seguridad
Para notificar una vulnerabilidad, seguir [`SECURITY.md`](SECURITY.md). No abrir incidencias públicas.
