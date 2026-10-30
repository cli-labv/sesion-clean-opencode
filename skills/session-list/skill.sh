#!/usr/bin/env bash
# skill: session-list
# Listado de sesiones opencode (session_v2), orden cronológico ascendente

session_list_get_tsv() {
  local db="$1"
  python3 - "$db" <<'PY'
import sqlite3, sys
db = sys.argv[1]
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
q = """SELECT id,
              coalesce(replace(replace(replace(title,char(9),' '),char(10),' '),char(13),' '),''),
              directory,
              datetime(time_created/1000,'unixepoch'),
              coalesce(parent_id,''),
              time_created
       FROM session_v2 ORDER BY time_created ASC, id ASC"""
for r in c.execute(q):
    print("\t".join(r))
PY
}

# Filtrar solo raíces
session_list_roots() {
  local tsv="$1"
  awk -F'\t' '$5==""{print}' "$tsv"
}

# Formatear para visual (fecha | id | nombre)
session_list_format_brief() {
  local tsv="$1"
  awk -F'\t' '{printf "%s | %s | %s\n", $4, $1, $2}' "$tsv"
}
