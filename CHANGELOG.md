# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Versionado [SemVer](https://semver.org/lang/es/).

## [1.0.0] - 2026-10-22

### Añadido

- Limpieza de sesiones de opencode en modo lista blanca estricto.
- `--init-list` para generar `keep-sessions.txt` con todas las sesiones raíz.
- Dry-run por defecto; `--apply` para borrar, con confirmación interactiva.
- Backup consistente de la DB (API de backup de SQLite) antes de borrar.
- `--vacuum` opcional para recuperar espacio.
- Borrado en cascada (`session`, `message`, `part`, `todo`, `session_message`).
- Tests automáticos contra una DB de ejemplo + CI con ShellCheck.

[1.0.0]: https://github.com/<usuario>/session-cleanup/releases/tag/v1.0.0
