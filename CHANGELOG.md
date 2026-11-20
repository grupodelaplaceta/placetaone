# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado: [SemVer](https://semver.org/lang/es/).

## [Sin publicar]

### Añadido
- Documentación de cumplimiento DEVAI: `AGENTS.md`, `SECURITY.md`, `CHANGELOG.md`, `docs/API.md` (inventario de API) y `docs/audits/2026-11-19-devai.md`.
- `.nvmrc` con Node.js 20, la versión que usa el CI.

### Cambiado
- Los bonos RBU caducan a los 3 meses de su emisión si no se canjean (antes, 7 días). Ver ADR-002.
- El saldo RBU ya canjeado no caduca: la caducidad diaria solo afecta a bonos sin canjear (migración 0061).

### Corregido
- Fechas con formato único y año completo. Vacías, no válidas o anteriores a 2000 se muestran como «—»; 2999 se muestra como «sin caducidad».
- Las transferencias programadas rechazan fechas no ISO, en el pasado o a más de 5 años.

### Añadido
- Aprobación automática de productos: un producto marcado se activa al guardarlo, con registro de quién lo configuró (migración 0062).

### Cambiado
- Panel de configuración rediseñado: ajustes agrupados por categoría, búsqueda, interruptores y selectores según el tipo de ajuste, y motivo obligatorio antes de proponer un cambio.
- Asistente «Nuevo impuesto» en cuatro pasos (impuesto, cómo se cobra, vigencia y revisión), con vista previa del efecto.

### Corregido
- Las versiones fiscales se publican con la regla de aprobador distinto del autor (antes se publicaban sin esa comprobación desde el panel).
- Eliminado el método «por tramos», que la base de datos no admite.

### Añadido
- Subvenciones y bonos con fondos autorizados: el importe se reserva al crearse; caducidad por convocatoria; caducidad diaria que libera la reserva.
- Reversión de abonos por el subvencionante o la Junta, con motivo y auditoría.
- Informe de justificación en JSON y PDF (admin y API de banca).

### Corregido
- Revertir un abono sin saldo ya no deja saldo negativo: lo disponible vuelve y el resto queda como deuda (migración 0064).
- La doble firma no admite excepciones: se retira la excepción de la Junta en ajustes y publicación fiscal.

### Añadido
- Lo recuperado de una deuda por reversión se vuelve a autorizar según la convocatoria (migración 0065).

### Añadido
- Documento de flujos con 9 diagramas validados (docs/FLUJOS.md).
- Pantalla de financiación con el flujo de subvenciones, concesiones con reserva, informe PDF, reversión, convocatorias y explicaciones actualizadas.

### Corregido
- Las concesiones y convocatorias ya no se crean directamente en la tabla: pasan por su operación, que reserva fondos.
- Las justificaciones pasan por la validación de elegibilidad.

### Nota
El proyecto no tiene todavía historial de commits convencionales (no es un repositorio Git). Las entradas anteriores a esta sección no se han reconstruido.
