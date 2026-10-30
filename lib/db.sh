#!/usr/bin/env bash
# lib/db.sh - acceso a DB opencode session_v2

# Listar sesiones en TSV: id, title, directory, datetime, parent_id
# Orden: cronológico ascendente (más antiguo -> más reciente)
db_list_sessions() {
  local db="$1"
  python3 - "$db" <<'PY'
import sqlite3, sys
db = sys.argv[1]
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
q = """SELECT id,
              coalesce(replace(replace(replace(title,char(9),' '),char(10),' '),char(13),' '),''),
              directory,
              datetime(time_created/1000,'unixepoch'),
              coalesce(parent_id,'')
       FROM session_v2 ORDER BY time_created ASC, id ASC"""
for r in c.execute(q):
    print("\t".join(r))
PY
}

# Backup con sqlite backup API
db_backup() {
  local db="$1" dest="$2"
  python3 - "$db" "$dest" <<'PY'
import sqlite3, sys, os
db, dest = sys.argv[1], sys.argv[2]
os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
src = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
dst = sqlite3.connect(dest)
src.backup(dst)
dst.close(); src.close()
print(os.path.getsize(dest))
PY
}

# Borrar sesiones
db_delete_sessions() {
  local db="$1" ids_file="$2"
  python3 - "$db" "$ids_file" <<'PY'
import sqlite3, sys
db, ids_file = sys.argv[1], sys.argv[2]
ids = [l.strip() for l in open(ids_file) if l.strip()]
if not ids:
    sys.exit(0)
c = sqlite3.connect(db)
c.execute("PRAGMA foreign_keys=ON")
c.execute("BEGIN IMMEDIATE")
ph = ",".join("?" * len(ids))
n_v2 = c.execute(f"DELETE FROM session_v2 WHERE id IN ({ph})", ids).rowcount
n_lg = c.execute(f"DELETE FROM session WHERE id IN ({ph})", ids).rowcount
c.execute(f"DELETE FROM message    WHERE session_id IN ({ph})", ids)
c.execute(f"DELETE FROM part       WHERE session_id IN ({ph})", ids)
c.execute(f"DELETE FROM todo       WHERE session_id IN ({ph})", ids)
c.execute(f"DELETE FROM session_message WHERE session_id IN ({ph})", ids)
c.commit()
resto = c.execute("SELECT count(*) FROM session_v2").fetchone()[0]
print(f"{n_v2}\t{n_lg}\t{resto}")
PY
}

# Vacuum
db_vacuum() {
  local db="$1"
  python3 - "$db" <<'PY'
import sqlite3, sys
db = sys.argv[1]
c = sqlite3.connect(db)
c.execute("PRAGMA foreign_keys=ON")
c.execute("VACUUM")
PY
}
