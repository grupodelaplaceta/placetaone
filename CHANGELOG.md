# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Versionado: [SemVer](https://semver.org/lang/es/).

## [Sin publicar]

### Añadido
- Documentación de cumplimiento DEVAI: `AGENTS.md`, `SECURITY.md`, `CHANGELOG.md`, `docs/API.md` (inventario de API) y `docs/audits/2026-11-19-devai.md`.
- `.nvmrc` con Node.js 20, la versión que usa el CI.

### Cambiado
- Los bonos RBU caducan a los 3 meses de su emisión si no se canjean (antes, 7 días). Ver ADR-002.
- El saldo RBU ya canjeado no caduca: la caducidad diaria solo afecta a bonos sin canjear (migración 0061).

### Nota
El proyecto no tiene todavía historial de commits convencionales (no es un repositorio Git). Las entradas anteriores a esta sección no se han reconstruido.
