#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/banner.sh"
init_colors
banner_show

if [ -x "$SCRIPT_DIR/session-cleanup-tui" ] && [ -t 0 ] && [ -t 1 ]; then
  "$SCRIPT_DIR/session-cleanup-tui" "$@"
  clear 2>/dev/null || printf '\033[2J\033[H'
  exit $?
fi

source "$SCRIPT_DIR/lib/term_menu.sh"
source "$SCRIPT_DIR/skills/session-list/skill.sh"
source "$SCRIPT_DIR/skills/whitelist/skill.sh"
source "$SCRIPT_DIR/skills/db-backup/skill.sh"

KEEP_FILE="${KEEP_FILE:-$SCRIPT_DIR/keep-sessions.txt}"
APPLY=0
ASSUME_YES=0
DO_BACKUP=1
DO_VACUUM=0
INIT_LIST=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --auto) APPLY=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --no-backup) DO_BACKUP=0 ;;
    --vacuum) DO_VACUUM=1 ;;
    --init-list) INIT_LIST=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage 2>/dev/null || true; exit 0 ;;
  esac
  shift
done

check_deps || exit 1
DB_PATH="$(get_opencode_db)"
[ -f "$DB_PATH" ] || { echo "${RED}ERROR:${RESET} No encuentro la base de datos: $DB_PATH" >&2; exit 1; }

calcular_borrado() {
  local tsv="$1" keep_file="$2"
  unset PARENT KEEP DELETE_IDS 2>/dev/null || true
  declare -gA PARENT KEEP
  DELETE_IDS=()
  while IFS=$'\t' read -r id _ _ _ parent; do [ -z "$id" ] && continue; PARENT["$id"]="$parent"; done < "$tsv"
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    read -r id _ <<<"$line"
    [[ "$id" == ses_* ]] || continue
    [ -n "${PARENT[$id]+x}" ] && KEEP["$id"]=1
  done < "$keep_file"
  for id in "${!PARENT[@]}"; do [ -n "${KEEP[$id]:-}" ] || DELETE_IDS+=("$id"); done
}

ejecutar_borrado() {
  local tsv="$1" total="$2" titulo="$3"
  local total_keep=${#KEEP[@]}
  local total_del=${#DELETE_IDS[@]}
  menu_clear
  menu_header "$titulo" "Orden: más antiguo → más reciente • Modo estricto"
  echo "  ${DIM}DB:${RESET}        $DB_PATH"
  echo "  ${DIM}Totales:${RESET}   ${BOLD}$total${RESET}"
  echo "  ${GREEN}Conservar:${RESET}  ${BOLD}$total_keep${RESET}"
  echo "  ${RED}Borrar:${RESET}     ${BOLD}$total_del${RESET}"
  echo
  [ "$total_del" -eq 0 ] && { echo "  ${GREEN}✓${RESET} Nada que borrar"; echo; pause; return 0; }
  if [ "$ASSUME_YES" -ne 1 ]; then
    echo "  ${RED}⚠${RESET} Se borrarán ${RED}${BOLD}$total_del${RESET} sesiones permanentemente"
    read -rp "  Escribe BORRAR para confirmar: " ans
    [ "$ans" = "BORRAR" ] || { echo "  ${DIM}Cancelado${RESET}"; echo; pause; return 0; }
  fi
  if [ "$DO_BACKUP" -eq 1 ]; then
    BK_DIR="$SCRIPT_DIR/backups"
    echo "  ${BLUE}→${RESET} Creando backup..."
    bkp=$(db_backup_create "$DB_PATH" "$BK_DIR")
    echo "  ${GREEN}✓${RESET} Guardado en ${CYAN}$bkp${RESET}"
  fi
  TSV_DEL="$(mktemp)"
  printf '%s\n' "${DELETE_IDS[@]}" > "$TSV_DEL"
  echo "  ${ORANGE}→${RESET} Borrando..."
  res=$(db_delete_sessions "$DB_PATH" "$TSV_DEL")
  IFS=$'\t' read -r n_v2 n_lg resto <<<"$res"
  echo "  ${GREEN}✓${RESET} Borradas: $n_v2 (v2) / $n_lg (legado) • Quedan: $resto"
  [ "$DO_VACUUM" -eq 1 ] && { echo "  ${BLUE}→${RESET} VACUUM..."; db_vacuum "$DB_PATH" 2>&1 || true; }
  rm -f "$TSV_DEL"
  echo
  echo "  ${GREEN}✓${RESET} Completado • Conservadas: ${GREEN}${BOLD}$total_keep${RESET}"
  echo
  pause
  return 0
}

menu_principal() {
  local tsv="$1" total="$2"
  local choice
  local roots=$(awk -F'\t' '$5==""{c++} END{print c+0}' "$tsv")
  local keep_cnt=0
  [ -f "$KEEP_FILE" ] && keep_cnt=$(grep -cE '^[[:space:]]*ses_' "$KEEP_FILE" 2>/dev/null || echo 0)
  menu_clear
  menu_header "SESSION-CLEANUP" "Limpieza segura de sesiones OpenCode • Modo lista blanca estricto"
  echo "  ${DIM}DB:${RESET}        ${CYAN}$DB_PATH${RESET}"
  echo "  ${DIM}Sesiones:${RESET}  ${BOLD}$total${RESET} ${DIM}(raíces: $roots)${RESET}"
  echo "  ${DIM}Conservar:${RESET} ${GREEN}$keep_cnt${RESET} ${DIM}(keep-sessions.txt)${RESET}"
  echo
  echo -e "  ${BOLD}MENÚ${RESET}"
  echo -e "  ${DIM}────────────────────────────────────────────────────────${RESET}"
  echo -e "  ${CYAN}${SEMIBOLD}1${RESET}) Ver todas las sesiones"
  echo -e "  ${CYAN}${SEMIBOLD}2${RESET}) Seleccionar conservar/eliminar"
  echo -e "  ${GREEN}${SEMIBOLD}3${RESET}) Limpieza automática (--auto)"
  echo -e "  ${BLUE}${SEMIBOLD}4${RESET}) Generar/actualizar keep-sessions.txt"
  echo -e "  ${MAGENTA}${SEMIBOLD}5${RESET}) Editar keep-sessions.txt (solo las ya guardadas)"
  echo -e "  ${RED}${SEMIBOLD}0${RESET}) Salir"
  echo -e "  ${DIM}────────────────────────────────────────────────────────${RESET}"
  echo
  read -rp "  ${CYAN}>${RESET} Opción [0-5]: " choice
  case "$choice" in
    1) choice="VER" ;;
    2) choice="SELECCIONAR" ;;
    3) choice="AUTO" ;;
    4) choice="INIT" ;;
    5) choice="EDITKEE" ;;
    0|q|Q) choice="SALIR" ;;
    *) choice="VER" ;;
  esac

  case "$choice" in
    VER)
      menu_clear
      menu_header "TODAS LAS SESIONES" "Más antiguo → más reciente • Total: $total"
      awk -F'\t' '{p=($5==""?"[RAÍZ]":"[SUB]"); printf "  %s  %s  %s  %s\n", $4, $1, p, $2}' "$tsv" | head -100
      [ "$total" -gt 100 ] && echo "  ${DIM}... +$((total-100))${RESET}"
      echo; pause; return 0 ;;
    SELECCIONAR)
      items=()
      while IFS=$'\t' read -r id title dir dt parent; do
        [ -z "$id" ] && continue
        short_title="$(format_title "$title" 48)"
        parent_info=""; [ -n "$parent" ] && parent_info=" ${DIM}(sub)${RESET}"
        display="$dt   ${CYAN}$id${RESET}   ${WHITE}$short_title${RESET}$parent_info"
        items+=("$id|$display|ON")
      done < "$tsv"
      mapfile -t sel < <(multiselect "ELEGIR CONSERVAR / ELIMINAR" "Marcadas [x]=CONSERVAR | Sin marcar=ELIMINAR • ESPACIO • A/N/I • ENTER • q" "${items[@]}") || { pause; return 0; }
      KEEP_TMP="$(mktemp)"
      echo "# Generado desde selección interactiva" > "$KEEP_TMP"
      echo "# Marcadas = CONSERVAR • Sin marcar = SE BORRARÁN" >> "$KEEP_TMP"
      echo "#" >> "$KEEP_TMP"
      for sid in "${sel[@]}"; do [ -z "$sid" ] && continue; awk -F'\t' -v want="$sid" '$1==want{printf "%s\t# %s | %s | %s\n", $1, $4, $1, $2; exit}' "$tsv"; done >> "$KEEP_TMP"
      calcular_borrado "$tsv" "$KEEP_TMP"
      ejecutar_borrado "$tsv" "$total" "RESUMEN - SELECCIÓN"
      rm -f "$KEEP_TMP"
      return 0 ;;
    AUTO)
      if [ ! -f "$KEEP_FILE" ]; then
        menu_clear; menu_header "LIMPIEZA AUTOMÁTICA" ""
        echo "  ${RED}ERROR:${RESET} No existe ${CYAN}$KEEP_FILE${RESET}"
        echo "  ${BLUE}→${RESET} Usa opción 4 (generar) o 5 (editar)"
        echo; pause; return 0
      fi
      calcular_borrado "$tsv" "$KEEP_FILE"
      ejecutar_borrado "$tsv" "$total" "RESUMEN - LIMPIEZA AUTOMÁTICA"
      return 0 ;;
    INIT)
      if [ -e "$KEEP_FILE" ] && [ "$FORCE" -ne 1 ]; then
        menu_clear; menu_header "GENERAR keep-sessions.txt" ""
        echo "  Ya existe keep-sessions.txt"
        echo; echo "    1) Sobreescribir"; echo "    2) Volver"
        echo; read -rp "  Selecciona: " ans
        [ "$ans" = "1" ] && FORCE=1 || { pause; return 0; }
      fi
      [ -e "$KEEP_FILE" ] && cp "$KEEP_FILE" "$KEEP_FILE.bak"
      whitelist_generate "$KEEP_FILE" "$tsv"
      count="$(whitelist_count_roots_in_file "$KEEP_FILE")"
      menu_clear; menu_header "keep-sessions.txt GENERADO" ""
      echo "  ${GREEN}✓${RESET} Creado/actualizado: ${CYAN}$KEEP_FILE${RESET} ${DIM}($count sesiones raíz)${RESET}"
      echo "  ${DIM}Edita el archivo o usa opción 5 para ajustar${RESET}"
      echo; pause; return 0 ;;
    EDITKEE)
      items=()
      declare -A K
      if [ -f "$KEEP_FILE" ]; then
        while IFS= read -r line; do
          [[ "$line" =~ ^[[:space:]]*# ]] && continue
          [[ "$line" =~ ^[[:space:]]*$ ]] && continue
          read -r id _ <<<"$line"
          [[ "$id" == ses_* ]] && K["$id"]=1
        done < "$KEEP_FILE"
      fi
      while IFS=$'\t' read -r id title dir dt parent; do
        [ -z "$id" ] && continue
        short_title="$(format_title "$title" 46)"
        parent_info=""; [ -n "$parent" ] && parent_info=" ${DIM}(sub)${RESET}"
        display="$dt   ${CYAN}$id${RESET}   ${WHITE}$short_title${RESET}$parent_info"
        if [ -n "${K[$id]:-}" ]; then items+=("$id|$display|ON"); else items+=("$id|$display|OFF"); fi
      done < "$tsv"
      mapfile -t sel < <(multiselect "EDITAR keep-sessions.txt" "[x]=EN ARCHIVO (se conservarán) • ESPACIO añadir/quitar • ENTER guardar" "${items[@]}") || { pause; return 0; }
      {
        echo "# Lista blanca de sesiones de opencode a CONSERVAR"
        echo "# Solo las listadas se conservan en modo AUTO"
        echo "# Todo lo demás se BORRARÁ"
        echo "#"
        for sid in "${sel[@]}"; do [ -z "$sid" ] && continue; awk -F'\t' -v want="$sid" '$1==want{printf "%s\t# %s | %s | %s\n", $1, $4, $1, $2; exit}' "$tsv"; done
      } > "$KEEP_FILE"
      menu_clear; menu_header "GUARDADO" ""
      echo "  ${GREEN}✓${RESET} Actualizado: ${CYAN}$KEEP_FILE${RESET}"
      echo; pause; return 0 ;;
    SALIR) clear 2>/dev/null || printf '\033[2J\033[H'; exit 0 ;;
  esac
}

if [ "$INIT_LIST" -eq 1 ]; then
  TSV="$(mktemp)"; trap 'rm -f "$TSV"' EXIT
  db_list_sessions "$DB_PATH" > "$TSV"
  if [ -e "$KEEP_FILE" ] && [ "$FORCE" -ne 1 ]; then echo "${YELLOW}⚠${RESET} Ya existe ${CYAN}$KEEP_FILE${RESET} ${DIM}(usa --force)${RESET}"; exit 0; fi
  [ -e "$KEEP_FILE" ] && cp "$KEEP_FILE" "$KEEP_FILE.bak"
  whitelist_generate "$KEEP_FILE" "$TSV"
  count="$(whitelist_count_roots_in_file "$KEEP_FILE")"
  echo "${GREEN}✓${RESET} Generado: ${CYAN}$KEEP_FILE${RESET} ${DIM}($count sesiones raíz)${RESET}"
  exit 0
fi

if [ "$APPLY" -eq 1 ]; then
  TSV_ALL="$(mktemp)"; trap 'rm -f "${TSV_ALL:-}"' EXIT
  db_list_sessions "$DB_PATH" > "$TSV_ALL"
  [ ! -f "$KEEP_FILE" ] && { echo "${RED}ERROR:${RESET} No existe $KEEP_FILE"; exit 1; }
  calcular_borrado "$TSV_ALL" "$KEEP_FILE"
  ejecutar_borrado "$TSV_ALL" "$(wc -l < "$TSV_ALL" | tr -d ' ')" "RESUMEN - LIMPIEZA AUTOMÁTICA"
  exit 0
fi

while true; do
  TSV_ALL="$(mktemp)"
  db_list_sessions "$DB_PATH" > "$TSV_ALL"
  total_all=$(wc -l < "$TSV_ALL" | tr -d ' ')
  [ "$total_all" -eq 0 ] && { echo "${YELLOW}Sin sesiones${RESET}"; rm -f "$TSV_ALL"; exit 0; }
  menu_principal "$TSV_ALL" "$total_all"
  rm -f "$TSV_ALL"
done
