#!/usr/bin/env bash
#
# cleanup-sessions.sh
# Aplicación directa (no interactiva) del borrado de sesiones opencode.
# Lee keep-sessions.txt (modo estricto) y borra todo lo que no esté listado.
# Uso típico:
#   ./cleanup-sessions.sh --init-list      # genera la lista blanca
#   # edita keep-sessions.txt y deja solo lo que conservar
#   ./cleanup-sessions.sh --apply          # borra (pide confirmar BORRAR)
#   ./cleanup-sessions.sh --apply --yes    # borra sin preguntar
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar módulos
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/db.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/term_menu.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/skills/session-list/skill.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/skills/whitelist/skill.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/skills/db-backup/skill.sh"

init_colors

KEEP_FILE="${KEEP_FILE:-$SCRIPT_DIR/keep-sessions.txt}"

APPLY=0
ASSUME_YES=0
DO_BACKUP=1
DO_VACUUM=0
INIT_LIST=0
FORCE=0

usage() {
  cat <<'EOF'
Uso:
  ./cleanup-sessions.sh               -> Muesta esta ayuda
  ./cleanup-sessions.sh --init-list   -> Generar keep-sessions.txt y salir
  ./cleanup-sessions.sh --apply       -> Borrar según keep-sessions.txt (pide confirmar)
  ./cleanup-sessions.sh --apply --yes -> Borrar sin confirmación
  ./cleanup-sessions.sh --vacuum      -> Compactar DB tras borrar (con --apply)
  ./cleanup-sessions.sh --no-backup   -> No hacer backup antes de borrar (con --apply)
  ./cleanup-sessions.sh -h|--help     -> Esta ayuda
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)        APPLY=1 ;;
    --yes|-y)       ASSUME_YES=1 ;;
    --no-backup)    DO_BACKUP=0 ;;
    --vacuum)       DO_VACUUM=1 ;;
    --init-list)    INIT_LIST=1 ;;
    --force)        FORCE=1 ;;
    -h|--help)      usage ;;
    *) echo "Opción desconocida: $1" >&2; exit 1 ;;
  esac
  shift
done

check_deps || exit 1
DB_PATH="$(get_opencode_db)"
[ -f "$DB_PATH" ] || { echo "${RED}ERROR:${RESET} No encuentro la base de datos: $DB_PATH" >&2; exit 1; }

# --- --init-list (no interactivo) ---
if [ "$INIT_LIST" -eq 1 ]; then
  TSV="$(mktemp)"; trap 'rm -f "$TSV"' EXIT
  db_list_sessions "$DB_PATH" > "$TSV"
  if [ -e "$KEEP_FILE" ] && [ "$FORCE" -ne 1 ]; then
    echo "${YELLOW}${BOLD}⚠${RESET}  Ya existe ${CYAN}$KEEP_FILE${RESET} ${DIM}(usa --force)${RESET}"
    exit 0
  fi
  [ -e "$KEEP_FILE" ] && cp "$KEEP_FILE" "$KEEP_FILE.bak"
  whitelist_generate "$KEEP_FILE" "$TSV"
  count="$(whitelist_count_roots_in_file "$KEEP_FILE")"
  echo "${GREEN}${BOLD}✓${RESET}  Generado: ${CYAN}$KEEP_FILE${RESET} ${DIM}($count sesiones raíz)${RESET}"
  echo "${BLUE}${SEMIBOLD}→${RESET}  Orden: ${BOLD}más antiguo → más reciente${RESET} | Formato: fecha | id | nombre"
  exit 0
fi

# --- --apply (modo directo, borra según keep-sessions.txt) ---
if [ "$APPLY" -ne 1 ]; then
  echo "${YELLOW}${BOLD}ℹ${RESET} Modo directo: indica ${CYAN}--apply${RESET} para borrar."
  echo "${BLUE}→${RESET} Genera primero la lista con ${CYAN}--init-list${RESET} y edita keep-sessions.txt."
  usage
fi

[ -f "$KEEP_FILE" ] || { echo "${RED}ERROR:${RESET} No existe $KEEP_FILE"; echo "${BLUE}→${RESET} Generalo con --init-list"; exit 1; }

TSV_ALL="$(mktemp)"; trap 'rm -f "${TSV_ALL:-}"' EXIT
db_list_sessions "$DB_PATH" > "$TSV_ALL"
total_all=$(wc -l < "$TSV_ALL" | tr -d ' ')
[ "$total_all" -eq 0 ] && { echo "${YELLOW}Sin sesiones${RESET}"; exit 0; }

declare -A PARENT KEEP
while IFS=$'\t' read -r id _ _ _ parent; do
  [ -z "$id" ] && continue
  PARENT["$id"]="$parent"
done < "$TSV_ALL"

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  read -r id _ <<<"$line"
  [[ "$id" == ses_* ]] || continue
  [ -n "${PARENT[$id]+x}" ] && KEEP["$id"]=1
done < "$KEEP_FILE"

DELETE_IDS=()
for id in "${!PARENT[@]}"; do
  [ -n "${KEEP[$id]:-}" ] || DELETE_IDS+=("$id")
done

total_keep=${#KEEP[@]}
total_del=${#DELETE_IDS[@]}

menu_clear
menu_header "RESUMEN - MODO DIRECTO" "Orden: más antiguo → más reciente • Modo estricto"
echo "  ${DIM}DB:${RESET}        $DB_PATH"
echo "  ${DIM}Totales:${RESET}   ${BOLD}$total_all${RESET}"
echo "  ${GREEN}${SEMIBOLD}Conservar:${RESET} ${GREEN}${BOLD}$total_keep${RESET}"
echo "  ${RED}${SEMIBOLD}Borrar:${RESET}    ${RED}${BOLD}$total_del${RESET}"
echo

if [ "$total_del" -eq 0 ]; then
  echo "  ${GREEN}${BOLD}✓${RESET} Nada que borrar"
  exit 0
fi

echo "  ${ORANGE}${SEMIBOLD}SE ELIMINARÁN${RESET} ${DIM}(fecha | id | nombre)${RESET}"
echo "  ${DIM}────────────────────────────────────────────────────────────────────────────────────────${RESET}"
for id in "${DELETE_IDS[@]}"; do
  grep -F "$id" "$TSV_ALL" | head -1
done | awk -F'\t' '{printf "    %s%s%s  %s%s%s  %s\n", "'$YELLOW''$DIM'", $4, "'$RESET'", "'$CYAN''$BOLD'", $1, "'$RESET'", $2}'
echo "  ${DIM}────────────────────────────────────────────────────────────────────────────────────────${RESET}"
echo

if [ "$ASSUME_YES" -ne 1 ]; then
  echo "  ${RED}${BOLD}ATENCIÓN:${RESET} Se borrarán ${RED}${BOLD}$total_del${RESET} sesiones permanentemente"
  read -rp "  Escribe BORRAR para confirmar: " ans
  [ "$ans" = "BORRAR" ] || { echo "  ${DIM}Cancelado${RESET}"; exit 1; }
fi

if [ "$DO_BACKUP" -eq 1 ]; then
  BK_DIR="$SCRIPT_DIR/backups"
  echo "  ${BLUE}${SEMIBOLD}→${RESET} Creando backup..."
  bkp=$(db_backup_create "$DB_PATH" "$BK_DIR")
  echo "  ${GREEN}${BOLD}✓${RESET} Guardado en ${CYAN}$bkp${RESET}"
fi

TSV_DEL="$(mktemp)"
printf '%s\n' "${DELETE_IDS[@]}" > "$TSV_DEL"
echo "  ${ORANGE}${SEMIBOLD}→${RESET} Borrando..."
res=$(db_delete_sessions "$DB_PATH" "$TSV_DEL")
IFS=$'\t' read -r n_v2 n_lg resto <<<"$res"
echo "  ${GREEN}${BOLD}✓${RESET} Borradas: $n_v2 (v2) / $n_lg (legado) • Quedan: $resto"
[ "$DO_VACUUM" -eq 1 ] && { echo "  ${BLUE}${SEMIBOLD}→${RESET} VACUUM..."; db_vacuum "$DB_PATH" 2>&1 || true; }
rm -f "$TSV_DEL"
echo
echo "  ${GREEN}${BOLD}✓${RESET} Completado • Conservadas: ${GREEN}${BOLD}$total_keep${RESET}"
