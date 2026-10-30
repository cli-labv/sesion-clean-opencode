#!/usr/bin/env bash
# skill: db-backup
# Backup consistente con SQLite backup API

db_backup_create() {
  local db="$1" backup_dir="$2"
  local ts="$(date +%Y%m%d-%H%M%S)"
  local dest="$backup_dir/$ts/opencode.db"
  mkdir -p "$(dirname "$dest")"
  local size
  size=$(python3 - "$db" "$dest" <<'PY'
import sqlite3, sys, os
db, dest = sys.argv[1], sys.argv[2]
src = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
dst = sqlite3.connect(dest)
src.backup(dst)
dst.close(); src.close()
print(os.path.getsize(dest))
PY
  )
  echo "$dest"
}
