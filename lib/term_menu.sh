#!/usr/bin/env bash
# lib/term_menu.sh - Menú 100% en terminal (robusto)

menu_clear() {
  clear 2>/dev/null || printf '\033[2J\033[H'
}

menu_header() {
  local title="$1" subtitle="${2:-}"
  echo -e "${MAGENTA}${SEMIBOLD}╭${RESET} ${CYAN}${SEMIBOLD}$title${RESET}"
  if [ -n "$subtitle" ]; then
    echo -e "${MAGENTA}${SEMIBOLD}│${RESET} ${BLUE}${SEMIBOLD}$subtitle${RESET}"
  fi
  echo -e "${MAGENTA}${SEMIBOLD}╰${RESET}"
  echo
}

multiselect() {
  local title="$1" subtitle="$2"
  shift 2
  local -a keys=()
  local -a labels=()
  local -a state=()
  local idx=0
  while [ $# -gt 0 ]; do
    local item="$1"
    local k="${item%%|*}"
    local rest="${item#*|}"
    local l="${rest%%|*}"
    local s="${rest##*|}"
    keys[$idx]="$k"
    labels[$idx]="$l"
    if [ "$s" = "ON" ]; then state[$idx]=1; else state[$idx]=0; fi
    idx=$((idx+1))
    shift
  done
  local count=$idx
  local cursor=0
  [ $count -eq 0 ] && return 1
  while true; do
    menu_clear
    menu_header "$title" "$subtitle"
    echo -e "${YELLOW}${SEMIBOLD}↑/↓${RESET} ${WHITE}mover${RESET}  ${CYAN}${SEMIBOLD}ESPACIO${RESET} ${WHITE}alternar${RESET}  ${GREEN}${SEMIBOLD}A${RESET} ${WHITE}conservar todo${RESET}  ${ORANGE}${SEMIBOLD}N${RESET} ${WHITE}eliminar todo${RESET}  ${MAGENTA}${SEMIBOLD}I${RESET} ${WHITE}invertir${RESET}  ${GREEN}${SEMIBOLD}ENTER${RESET} ${WHITE}aplicar${RESET}  ${RED}${SEMIBOLD}q${RESET} ${WHITE}cancelar${RESET}"
    echo
    local i=0
    while [ $i -lt $count ]; do
      local mark=" "
      local action=""
      if [ "${state[$i]:-0}" = "1" ]; then
        mark="${GREEN}${SEMIBOLD}x${RESET}"
        action="${GREEN}${SEMIBOLD}[CONSERVAR]${RESET}"
      else
        mark=" "
        action="${RED}${SEMIBOLD}[ELIMINAR ]${RESET}"
      fi
      if [ $i -eq $cursor ]; then
        echo -e "  ${ORANGE}${SEMIBOLD}>${RESET} [${mark}] ${action} ${WHITE}${SEMIBOLD}${labels[$i]}${RESET}"
      else
        echo -e "    [${mark}] ${action} ${DIM}${labels[$i]}${RESET}"
      fi
      i=$((i+1))
    done
    echo
    local m=0 mc=0 md=0
    while [ $m -lt $count ]; do
      if [ "${state[$m]:-0}" = "1" ]; then mc=$((mc+1)); else md=$((md+1)); fi
      m=$((m+1))
    done
    echo -e "${GREEN}${SEMIBOLD}A CONSERVAR:${RESET} ${WHITE}${SEMIBOLD}$mc${RESET}  ${DIM}|${RESET}  ${RED}${SEMIBOLD}A ELIMINAR:${RESET} ${WHITE}${SEMIBOLD}$md${RESET}  ${DIM}|${RESET}  ${DIM}Total:${RESET} ${WHITE}${SEMIBOLD}$count${RESET}"
    echo
    if [ ! -t 0 ]; then
      # No interactivo: marcar todo por defecto
      local j=0
      while [ $j -lt $count ]; do
        if [ "${state[$j]:-0}" = "1" ]; then echo "${keys[$j]}"; fi
        j=$((j+1))
      done
      return 0
    fi
    local key=""
    if ! IFS= read -rsn1 key 2>/dev/null; then
      local j=0
      while [ $j -lt $count ]; do
        if [ "${state[$j]:-0}" = "1" ]; then echo "${keys[$j]}"; fi
        j=$((j+1))
      done
      return 0
    fi
    if [ "$key" = $'\x1b' ]; then
      local k2=""
      IFS= read -rsn2 k2 2>/dev/null || true
      case "$k2" in
        '[A') cursor=$((cursor-1)); [ $cursor -lt 0 ] && cursor=$((count-1)) ;;
        '[B') cursor=$((cursor+1)); [ $cursor -ge $count ] && cursor=0 ;;
      esac
    elif [ "$key" = " " ]; then
      if [ "${state[$cursor]:-0}" = "1" ]; then state[$cursor]=0; else state[$cursor]=1; fi
    elif [ "$key" = "a" ] || [ "$key" = "A" ]; then
      local j=0; while [ $j -lt $count ]; do state[$j]=1; j=$((j+1)); done
    elif [ "$key" = "n" ] || [ "$key" = "N" ]; then
      local j=0; while [ $j -lt $count ]; do state[$j]=0; j=$((j+1)); done
    elif [ "$key" = "i" ] || [ "$key" = "I" ]; then
      local j=0; while [ $j -lt $count ]; do if [ "${state[$j]:-0}" = "1" ]; then state[$j]=0; else state[$j]=1; fi; j=$((j+1)); done
    elif [ -z "$key" ] || [ "$key" = $'\n' ] || [ "$key" = $'\r' ]; then
      local j=0
      while [ $j -lt $count ]; do
        if [ "${state[$j]:-0}" = "1" ]; then echo "${keys[$j]}"; fi
        j=$((j+1))
      done
      return 0
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      return 1
    fi
  done
}

menu_select() {
  local title="$1" subtitle="$2"
  shift 2
  local -a keys=()
  local -a labels=()
  local -a descs=()
  local idx=0
  while [ $# -gt 0 ]; do
    local item="$1"
    local k="${item%%|*}"
    local rest="${item#*|}"
    local l="${rest%%|*}"
    local d="${rest#*|}"
    [ "$d" = "$rest" ] && d=""
    keys[$idx]="$k"
    labels[$idx]="$l"
    descs[$idx]="$d"
    idx=$((idx+1))
    shift
  done
  local count=$idx
  local cursor=0
  [ $count -eq 0 ] && return 1
  while true; do
    menu_clear
    menu_header "$title" "$subtitle"
    echo -e "${YELLOW}${SEMIBOLD}↑/↓${RESET} ${WHITE}${SEMIBOLD}mover${RESET}  ${GREEN}${SEMIBOLD}ENTER${RESET} ${WHITE}${SEMIBOLD}seleccionar${RESET}  ${RED}${SEMIBOLD}q${RESET} ${WHITE}${SEMIBOLD}salir${RESET}"
    echo
    local i=0
    while [ $i -lt $count ]; do
      if [ $i -eq $cursor ]; then
        echo -e "  ${ORANGE}${SEMIBOLD}▸${RESET} ${CYAN}${SEMIBOLD}${labels[$i]}${RESET}"
        [ -n "${descs[$i]:-}" ] && echo -e "    ${MAGENTA}${SEMIBOLD}›${RESET} ${WHITE}${SEMIBOLD}${descs[$i]}${RESET}"
      else
        echo -e "    ${WHITE}${SEMIBOLD}${labels[$i]}${RESET}"
        [ -n "${descs[$i]:-}" ] && echo -e "    ${DIM}${SEMIBOLD}${descs[$i]}${RESET}"
      fi
      echo
      i=$((i+1))
    done
    if [ ! -t 0 ]; then
      echo "${keys[$cursor]}"
      return 0
    fi
    local key=""
    if ! IFS= read -rsn1 key 2>/dev/null; then
      echo "${keys[$cursor]}"
      return 0
    fi
    if [ "$key" = $'\x1b' ]; then
      local k2=""
      IFS= read -rsn2 k2 2>/dev/null || true
      case "$k2" in
        '[A') cursor=$((cursor-1)); [ $cursor -lt 0 ] && cursor=$((count-1)) ;;
        '[B') cursor=$((cursor+1)); [ $cursor -ge $count ] && cursor=0 ;;
      esac
    elif [ -z "$key" ] || [ "$key" = $'\n' ] || [ "$key" = $'\r' ]; then
      echo "${keys[$cursor]}"
      return 0
    elif [ "$key" = "q" ] || [ "$key" = "Q" ]; then
      return 1
    fi
  done
}

pause() {
  echo
  read -rp "$(echo -e ${CYAN}${SEMIBOLD}[${RESET}${WHITE}${SEMIBOLD}ENTER${RESET}${CYAN}${SEMIBOLD}]${RESET} ${WHITE}${SEMIBOLD}para continuar${RESET})"
}
