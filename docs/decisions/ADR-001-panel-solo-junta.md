# ADR-001: el panel de administración es solo para la Junta

- Estado: aceptado (aprobado en la conversación del 2026-11-19). Firma del responsable técnico: PENDIENTE (DIP).
- Contexto: el panel de Placeta debe estar reservado a la Junta. La operativa de cada entidad se gestiona por su API.
- Decisión: `staffFrom` (`src/lib/supabase.ts`) solo acepta el rol `admin`. Cualquier otro rol de personal pierde el acceso al panel.
- Consecuencias: las listas de roles que aún aparecen en algunas rutas (por ejemplo `src/app/api/rpc/[fn]/route.ts` y `src/app/api/admin/r/[res]/route.ts`) ya no tienen efecto. Retirarlas es la deuda TECH-004.
- Verificación: las rutas del panel se revisaron una a una (DEV-015 de la auditoría).
