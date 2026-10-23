#!/usr/bin/env bash
#
# cleanup-sessions.sh
# Borra sesiones de opencode conservando SOLO las de la lista blanca.
# Versión 2: usa python3+sqlite directamente (la tabla viva es session_v2;
# el subcomando 'opencode db' ya no existe en opencode actual).
#
# Uso:
#   ./cleanup-sessions.sh                 -> simulacion (dry-run), no borra nada
#   ./cleanup-sessions.sh --apply         -> borra (pide confirmacion)
#   ./cleanup-sessions.sh --apply --yes   -> borra sin preguntar
#   ./cleanup-sessions.sh --init-list     -> genera/regenera keep-sessions.txt con TODAS las sesiones raiz
#   ./cleanup-sessions.sh --apply --vacuum -> ademas compacta la DB para recuperar disco
#
# Reglas:
#   - keep-sessions.txt = sesiones a CONSERVAR (whitelist).
#   - MODO ESTRICTO: solo sobreviven las sesiones listadas literalmente.
#     Las sub-sesiones (hijas) de una sesion conservada SE BORRAN tambien.
#   - Antes de --apply se hace copia de seguridad consistente de la DB (sqlite backup API).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_FILE="${KEEP_FILE:-$SCRIPT_DIR/keep-sessions.txt}"

APPLY=0
ASSUME_YES=0
DO_BACKUP=1
DO_VACUUM=0
INIT_LIST=0
FORCE=0

usage() { awk 'NR<3{next} /^[^#]/{exit} {sub(/^# ?/,""); print}' "$0"; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)        APPLY=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    --no-backup)    DO_BACKUP=0 ;;
    --vacuum)       DO_VACUUM=1 ;;
    --init-list)    INIT_LIST=1 ;;
    --force)        FORCE=1 ;;
    -h|--help)      usage ;;
    *) echo "Opcion desconocida: $1" >&2; exit 1 ;;
  esac
  shift
done

command -v opencode >/dev/null 2>&1 || { echo "ERROR: 'opencode' no esta en el PATH." >&2; exit 1; }
command -v python3  >/dev/null 2>&1 || { echo "ERROR: 'python3' no esta en el PATH." >&2; exit 1; }

DB_PATH="$(opencode debug paths 2>/dev/null | awk '$1=="db"{print $2}')"
[ -z "$DB_PATH" ] && DB_PATH="$HOME/.local/share/opencode/opencode.db"
[ -f "$DB_PATH" ] || { echo "ERROR: no encuentro la base de datos: $DB_PATH" >&2; exit 1; }

# Helper python: lista sesiones de la tabla viva (session_v2) en TSV.
py_list() {
  python3 - "$DB_PATH" <<'PY'
import sqlite3, sys, time
db = sys.argv[1]
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
q = """SELECT id,
              coalesce(replace(replace(replace(title,char(9),' '),char(10),' '),char(13),' '),''),
              directory,
              datetime(time_created/1000,'unixepoch'),
              coalesce(parent_id,'')
       FROM session_v2 ORDER BY time_created DESC"""
for r in c.execute(q):
    print("\t".join(r))
PY
}

# Helper python: borra por ids de la tabla viva + tablas legadas (con cascada).
py_delete() {
  python3 - "$DB_PATH" "$1" <<'PY'
import sqlite3, sys
db, ids_file = sys.argv[1], sys.argv[2]
ids = [l.strip() for l in open(ids_file) if l.strip()]
if not ids:
    print("  Nada que borrar."); sys.exit(0)
c = sqlite3.connect(db)
c.execute("PRAGMA foreign_keys=ON")
ph = ",".join("?" * len(ids))
cur = c.execute("BEGIN IMMEDIATE")
n_v2 = c.execute(f"DELETE FROM session_v2 WHERE id IN ({ph})", ids).rowcount
n_lg = c.execute(f"DELETE FROM session WHERE id IN ({ph})", ids).rowcount
# por si alguna FK no estaba activa en datos legados
c.execute(f"DELETE FROM message    WHERE session_id IN ({ph})", ids)
c.execute(f"DELETE FROM part       WHERE session_id IN ({ph})", ids)
c.execute(f"DELETE FROM todo       WHERE session_id IN ({ph})", ids)
c.execute(f"DELETE FROM session_message WHERE session_id IN ({ph})", ids)
c.commit()
resto = c.execute("SELECT count(*) FROM session_v2").fetchone()[0]
print(f"  Borradas: {n_v2} sesiones (v2) / {n_lg} (legado). Quedan {resto} en session_v2.")
PY
}

py_vacuum() {
  python3 - "$DB_PATH" <<'PY'
import sqlite3, sys, os
db = sys.argv[1]
for suf in ("-wal", "-shm"):
    p = db + suf
    if os.path.exists(p):
        print(f"  aviso: {p} existe; VACUUM puede fallar si opencode esta activo.")
c = sqlite3.connect(db)
c.execute("PRAGMA foreign_keys=ON")
c.execute("VACUUM")
print("  VACUUM ok.")
PY
}

py_backup() {
  python3 - "$DB_PATH" "$1" <<'PY'
import sqlite3, sys, os
db, dest = sys.argv[1], sys.argv[2]
src = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
dst = sqlite3.connect(dest)
src.backup(dst)
dst.close(); src.close()
print(f"  Backup listo: {dest} ({os.path.getsize(dest)//(1024*1024)} MB)")
PY
}

# ---------- modo --init-list ----------
if [ "$INIT_LIST" -eq 1 ]; then
  if [ -e "$KEEP_FILE" ] && [ "$FORCE" -ne 1 ]; then
    echo "Ya existe $KEEP_FILE (usa --force para sobreescribir)."
    exit 0
  fi
  [ -e "$KEEP_FILE" ] && cp "$KEEP_FILE" "$KEEP_FILE.bak"
  {
    echo "# Lista blanca de sesiones de opencode a CONSERVAR."
    echo "# Una sesion por linea. Las que NO aparezcan aqui se BORRARAN."
    echo "# Para borrar una sesion, elimina su linea (o comentala con #)."
    echo "# Formato: <ses_id>   # <fecha> | <directorio> | <titulo>"
    echo "#"
    py_list | awk -F'\t' '$5==""{printf "%s\t# %s | %s | %s\n", $1, $4, $3, $2}'
  } > "$KEEP_FILE"
  echo "Generado: $KEEP_FILE  ($(grep -cE '^ses_' "$KEEP_FILE") sesiones raiz)"
  echo "Edita ese archivo: deja SOLO las sesiones que quieras conservar."
  exit 0
fi

# ---------- validar lista ----------
if [ ! -f "$KEEP_FILE" ]; then
  echo "ERROR: no existe $KEEP_FILE" >&2
  echo "Genera la lista primero con:  $0 --init-list" >&2
  exit 1
fi

TSV="$(mktemp)"
IDS_DEL="$(mktemp)"
cleanup() { rm -f "$TSV" "$IDS_DEL"; }
trap cleanup EXIT
py_list > "$TSV"

declare -A PARENT KEEP

while IFS=$'\t' read -r id _ _ _ parent; do
  [ -z "$id" ] && continue
  PARENT["$id"]="$parent"
done < "$TSV"

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  read -r id _ <<<"$line"
  [[ "$id" == ses_* ]] || continue
  if [ -z "${PARENT[$id]+x}" ]; then
    echo "AVISO: '$id' no existe en la DB (ignorada)." >&2
    continue
  fi
  KEEP["$id"]=1
done < "$KEEP_FILE"

# MODO ESTRICTO: no se conservan ni hijas ni ancestros de lo listado;
# solo sobreviven las ids listadas literalmente en keep-sessions.txt.

# ---------- calcular a borrar ----------
DELETE_IDS=()
for id in "${!PARENT[@]}"; do
  [ -n "${KEEP[$id]:-}" ] || DELETE_IDS+=("$id")
done

total_all=${#PARENT[@]}
total_keep=${#KEEP[@]}
total_del=${#DELETE_IDS[@]}

echo "DB                    : $DB_PATH"
echo "Sesiones totales (v2) : $total_all"
echo "A conservar           : $total_keep"
echo "A borrar              : $total_del"
echo

if [ "$total_del" -eq 0 ]; then
  echo "Nada que borrar."
  exit 0
fi

echo "Sesiones que se borrarian:"
for id in "${DELETE_IDS[@]}"; do
  awk -F'\t' -v want="$id" '$1==want {printf "  %s  %s  %s  %s\n", $3, $4, $1, $2}' "$TSV"
done
echo

if [ "$APPLY" -ne 1 ]; then
  echo "MODO SIMULACION (dry-run). Para borrar de verdad: $0 --apply"
  exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Esto BORRARA $total_del sesiones de forma permanente. Escribe 'BORRAR' para continuar: " ans
  [ "$ans" = "BORRAR" ] || { echo "Cancelado."; exit 1; }
fi

if [ "$DO_BACKUP" -eq 1 ]; then
  BK_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BK_DIR"
  echo "Copia de seguridad (consistente, sqlite backup API)..."
  py_backup "$DB_PATH" "$BK_DIR/opencode.db"
fi

printf '%s\n' "${DELETE_IDS[@]}" > "$IDS_DEL"
echo "Borrando..."
py_delete "$IDS_DEL"

if [ "$DO_VACUUM" -eq 1 ]; then
  echo "Compactando DB (VACUUM)..."
  py_vacuum || echo "  VACUUM fallo (normal si hay opencode activo)." >&2
fi

echo "Listo. Objetivo: conservar $total_keep sesiones."
