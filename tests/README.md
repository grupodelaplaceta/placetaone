# Pruebas

- `npm run test` ejecuta la suite de verificación del repositorio (`verificacion/ejecutar.sh`): tipos del SDK, de la API y de las pantallas, simulador del SDK, SQL y coherencia de llamadas.
- Las pruebas de base de datos están en `supabase/tests/` (aceptación, concurrencia y restauración). Las ejecuta el job `db` del CI en PostgreSQL 16.
- `verificacion/pruebas_db.sql`: pruebas de idempotencia y de reglas de dinero. Ejecutar solo en una base de pruebas.
- PENDIENTE: pruebas unitarias de autorización por rol y de rutas de API. Requieren elegir un ejecutor de pruebas (decisión de dependencias).
