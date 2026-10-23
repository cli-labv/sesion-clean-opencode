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
```

Copia la plantilla de la lista blanca:

```bash
cp keep-sessions.example.txt keep-sessions.txt
```

## Uso

```bash
# 1. Genera keep-sessions.txt con TODAS las sesiones raiz
./cleanup-sessions.sh --init-list

# 2. Edita keep-sessions.txt y deja SOLO las que quieras conservar
$EDITOR keep-sessions.txt

# 3. Simulacion: muestra que se borraria, sin tocar nada
./cleanup-sessions.sh

# 4. Borrar (pide escribir BORRAR para confirmar)
./cleanup-sessions.sh --apply

# 5. Borrar sin preguntar (para scripts)
./cleanup-sessions.sh --apply --yes
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

## Seguridad

- Por defecto **no borra nada**: es dry-run hasta que pasas `--apply`.
- Cierra opencode antes de `--apply` (o al menos antes de `--vacuum`) para evitar
  bloqueos y resultados inconsistentes.
- `keep-sessions.txt` y `backups/` están en `.gitignore`: contienen tus IDs,
  títulos y datos personales. No los subas a git.

## Licencia

MIT. Ver [LICENSE](LICENSE).
