# session-cleanup

Limpia la base de datos de sesiones de [opencode](https://opencode.ai) conservando
solo las sesiones que tú decidas (modo lista blanca / estricto).

Pensado para cuando la DB acumula miles de sesiones y quieres recuperar espacio
sin perder las que te importan.

## Requisitos

- `bash` 4+ (usa arrays asociativos)
- `python3` (accede a SQLite con la librería estándar)
- `opencode` en el `PATH` (solo para localizar la DB)

## Instalación

```bash
git clone https://github.com/<usuario>/session-cleanup.git
cd session-cleanup
chmod +x cleanup-sessions.sh
cp keep-sessions.example.txt keep-sessions.txt
```

## Uso

### Flujo interactivo (menú al iniciar)

```bash
# 1. Abre el menú principal
./start.sh

# 2. Elige una opción del menú:
#    - VER todas las sesiones
#    - BORRAR: borrado rápido usando keep-sessions.txt (modo estricto)
#    - SELECCIONAR qué conservar / eliminar (multi-marca con ESPACIO)
#    - INIT: generar keep-sessions.txt
#    - SALIR

# 3. Desde el menú, genera la lista si no existe:
#    elige INIT -> edita keep-sessions.txt -> elige BORRAR

# 4. Confirma el borrado (escribe BORRAR) o cancela
```

### Flujo directo (sin menú, para scripts/CI)

```bash
# 1. Genera keep-sessions.txt con TODAS las sesiones raíz
./cleanup-sessions.sh --init-list

# 2. Edita keep-sessions.txt y deja SOLO las que quieras conservar
$EDITOR keep-sessions.txt

# 3. Borrar (pide escribir BORRAR para confirmar)
./cleanup-sessions.sh --apply

# 4. Borrar sin preguntar (para scripts)
./cleanup-sessions.sh --apply --yes

# 5. Compactar la DB tras borrar
./cleanup-sessions.sh --apply --vacuum
```

### Opciones

| Opción | Descripción |
| --- | --- |
| `--init-list` | Genera/regenera `keep-sessions.txt` con todas las sesiones raíz |
| `--force` | Permite que `--init-list` sobrescriba una lista existente |
| `--apply` | Borra de verdad (sin esta opción solo simula) |
| `--yes`, `-y` | No pide confirmación interactiva |
| `--no-backup` | No hace copia de seguridad antes de borrar |
| `--vacuum` | Compacta la DB después de borrar (recupera disco) |
| `-h`, `--help` | Muestra la ayuda |

## Cómo funciona

- Lee la tabla viva `session_v2` y la tabla legada `session`.
- **Modo estricto**: solo sobreviven las IDs listadas literalmente en
  `keep-sessions.txt`. Las sub-sesiones (hijas) de una sesión conservada también
  se borran; para mantener una hija, añádela a la lista.
- Antes de `--apply` crea una copia consistente de la DB con la API de backup de
  SQLite en `backups/<fecha>/opencode.db`.
- Borra en cascada los registros asociados (`message`, `part`, `todo`,
  `session_message`).

## Ejemplo

`keep-sessions.example.txt` es la plantilla de la lista blanca. Para probar el
script sin arriesgar tu DB real:

```bash
make test
```

Los tests crean una SQLite de ejemplo con sesiones ficticias y un `opencode`
falso en el `PATH`; verifican dry-run, borrado en cascada, modo estricto e
idempotencia. Nunca tocan `~/.local/share/opencode/`.

## Estructura

```
start.sh                    menú principal interactivo (punto de inicio)
cleanup-sessions.sh         modo directo/no interactivo (aplicar borrado)
keep-sessions.example.txt   plantilla de lista blanca
tests/run-tests.sh          tests contra una DB de ejemplo
.github/workflows/ci.yml    CI: bash -n + ShellCheck + tests
Makefile                    make test / lint / check / clean
```

## Seguridad

- Por defecto **no borra nada**: es dry-run hasta que pasas `--apply`.
- Cierra opencode antes de `--apply` (o al menos antes de `--vacuum`) para evitar
  bloqueos y resultados inconsistentes.
- `keep-sessions.txt`, `backups/` y `*.db` están en `.gitignore`: contienen tus
  IDs, títulos y datos personales. No los subas a git.

## Contribuir

Ver [CONTRIBUTING.md](CONTRIBUTING.md). Para vulnerabilidades, ver
[SECURITY.md](SECURITY.md). Historial de cambios en [CHANGELOG.md](CHANGELOG.md).

## Licencia

MIT. Ver [LICENSE](LICENSE).
