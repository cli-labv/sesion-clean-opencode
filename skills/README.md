# Skills reutilizables para apps CLI

Este directorio contiene funcionalidades descompuestas de `start.sh` para reutilizarlas en otras herramientas CLI con interfaz tipo terminal.

## Estructura

| Skill | Descripción | Uso |
|---|---|---|
| `session-list/` | Listado de sesiones desde SQLite de opencode, con orden cronológico. | Obtener sesiones formateadas para mostrar en menú/lista. |
| `session-select/` | Selección múltiple interactiva con whiptail/checklist. | Seleccionar qué sesiones conservar/borrar con espacio. |
| `whitelist/` | Gestión de `keep-sessions.txt` (whitelist estricto). | Modo tradicional por archivo. |
| `db-backup/` | Backup consistente con API SQLite. | Copia de seguridad antes de operaciones destructivas. |
| `tui-menu/` | Menú interactivo principal con colores y semibold. | Navegación unificada para apps CLI. |

Cada skill incluye:
- `skill.sh` - Funciones exportables
- `README.md` - Documentación de uso
- `example.sh` - Ejemplo mínimo de integración

## Filosofía de diseño

- **Modular**: cada archivo hace una cosa
- **Reutilizable**: sin dependencias del resto salvo bash + python3
- **TUI consistente**: colores, semibold, jerarquía clara
- **Sin inventar APIs**: lee directamente `session_v2` de opencode
- **Orden cronológico**: más antiguo -> más reciente
