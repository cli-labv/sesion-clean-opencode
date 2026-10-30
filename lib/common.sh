#!/usr/bin/env bash
# lib/common.sh - utilidades comunes para session-cleanup
# Reutilizable en otras apps CLI

# Colores y estilos semibold
init_colors() {
  if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    BOLD="$(tput bold)"
    SEMIBOLD="$BOLD"
    DIM="$(tput dim)"
    RESET="$(tput sgr0)"
    CYAN="$(tput setaf 6)"
    BLUE="$(tput setaf 4)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    ORANGE="$(tput setaf 208 2>/dev/null || tput setaf 3)"
    RED="$(tput setaf 1)"
    MAGENTA="$(tput setaf 5)"
    WHITE="$(tput setaf 7)"
  else
    BOLD=$'\033[1m'
    SEMIBOLD=$'\033[1m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
    CYAN=$'\033[36m'
    BLUE=$'\033[34m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    ORANGE=$'\033[38;5;208m'
    RED=$'\033[31m'
    MAGENTA=$'\033[35m'
    WHITE=$'\033[37m'
  fi
}

# Obtener DB de opencode
get_opencode_db() {
  local db_path=""
  if command -v opencode >/dev/null 2>&1; then
    db_path="$(opencode debug paths 2>/dev/null | awk '$1=="db"{print $2}')"
  fi
  [ -z "$db_path" ] && db_path="$HOME/.local/share/opencode/opencode.db"
  echo "$db_path"
}

# Comprobar deps
check_deps() {
  command -v opencode >/dev/null 2>&1 || { echo "${RED}ERROR:${RESET} 'opencode' no está en el PATH" >&2; return 1; }
  command -v python3  >/dev/null 2>&1 || { echo "${RED}ERROR:${RESET} 'python3' no está en el PATH" >&2; return 1; }
  return 0
}

# Formatear título para display (truncado si muy largo)
format_title() {
  local title="$1"
  local max="${2:-40}"
  # Eliminar saltos y espacios múltiples
  title="$(echo "$title" | tr -d '\n\r' | tr -s ' ')"
  if [ ${#title} -gt "$max" ]; then
    echo "${title:0:$((max-3))}..."
  else
    echo "$title"
  fi
}
