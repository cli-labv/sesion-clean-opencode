#!/usr/bin/env bash
# skill: whitelist
# Gestión de keep-sessions.txt

whitelist_generate() {
  local keep_file="$1" tsv="$2"
  {
    echo "# Lista blanca de sesiones de opencode a CONSERVAR"
    echo "# Una sesión por línea. Las que NO aparezcan aquí se BORRARÁN."
    echo "# Formato: <ses_id>   # <fecha> | <id> | <nombre>"
    echo "#"
    awk -F'\t' '$5==""{printf "%s\t# %s | %s | %s\n", $1, $4, $1, $2}' "$tsv"
  } > "$keep_file"
}

whitelist_load() {
  local keep_file="$1" tsv="$2"
  # Retorna IDs a conservar
  declare -A PARENT
  while IFS=$'\t' read -r id _ _ _ parent; do
    [ -z "$id" ] && continue
    PARENT["$id"]="$parent"
  done < "$tsv"
  
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    read -r id _ <<<"$line"
    [[ "$id" == ses_* ]] || continue
    [ -n "${PARENT[$id]+x}" ] && echo "$id"
  done < "$keep_file"
}

whitelist_count_roots_in_file() {
  grep -cE '^[[:space:]]*ses_' "$1" 2>/dev/null || echo 0
}
