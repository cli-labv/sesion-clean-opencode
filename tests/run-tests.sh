#!/usr/bin/env bash
#
# tests/run-tests.sh
# Pruebas de start.sh contra una base de datos de EJEMPLO.
# No toca tu base real: crea un entorno temporal y un 'opencode' falso en PATH.
#
# Uso: ./tests/run-tests.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/start.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL $1" >&2; }

assert_eq() { # <esperado> <real> <mensaje>
  if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (esperado='$1' real='$2')"; fi
}

assert_contains() { # <texto> <subcadena> <mensaje>
  if [[ "$1" == *"$2"* ]]; then ok "$3"; else fail "$3 (no contiene '$2')"; fi
}

# ---------- entorno de ejemplo ----------
DB="$TMP/opencode.db"
mkdir -p "$TMP/bin"

cat > "$TMP/bin/opencode" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "debug" ] && [ "${2:-}" = "paths" ]; then
  echo "db $DEMO_DB"
  exit 0
fi
exit 1
EOF
chmod +x "$TMP/bin/opencode"
export PATH="$TMP/bin:$PATH"
export DEMO_DB="$DB"

python3 - "$DB" <<'PY'
import sqlite3, sys
db = sys.argv[1]
c = sqlite3.connect(db)
c.executescript("""
CREATE TABLE session_v2 (
  id TEXT PRIMARY KEY, title TEXT, directory TEXT,
  time_created INTEGER, parent_id TEXT
);
CREATE TABLE session (
  id TEXT PRIMARY KEY, title TEXT, directory TEXT,
  time_created INTEGER, parent_id TEXT
);
CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT);
CREATE TABLE part (id TEXT PRIMARY KEY, session_id TEXT);
CREATE TABLE todo (id TEXT PRIMARY KEY, session_id TEXT);
CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT);
""")

# (id, titulo, padre)  -> 3 raices, 1 hija colgando de la raiz 1
rows = [
    ("ses_keep0000000000000000000001", "raiz conservada", None),
    ("ses_keep0000000000000000000002", "otra raiz conservada", None),
    ("ses_del00000000000000000000003", "raiz a borrar", None),
    ("ses_del00000000000000000000004", "hija de la raiz 1", "ses_keep0000000000000000000001"),
]
for i, (sid, title, parent) in enumerate(rows):
    c.execute(
        "INSERT INTO session_v2 (id,title,directory,time_created,parent_id) VALUES (?,?,?,?,?)",
        (sid, title, "/tmp/demo", 1700000000000 + i * 1000, parent),
    )
    c.execute("INSERT INTO session (id,title,directory,time_created,parent_id) VALUES (?,?,?,?,?)",
              (sid, title, "/tmp/demo", 1700000000000 + i * 1000, parent))
    for table in ("message", "part", "todo", "session_message"):
        c.execute(f"INSERT INTO {table} (id,session_id) VALUES (?,?)", (f"{table}_{i}", sid))
c.commit()
PY

KEEP="$TMP/keep-sessions.txt"
run() { KEEP_FILE="$KEEP" "$SCRIPT" "$@"; }

echo "== --init-list"
out="$(run --init-list)"
grep -q '^ses_keep0000000000000000000001' "$KEEP" \
  && ok "genera la lista con las sesiones" || fail "no genero la lista"
assert_contains "$out" "sesiones raiz" "informa cuantas sesiones raiz hay"

# Solo conservamos la primera raiz; el resto (incluida su hija) debe caer.
cat > "$KEEP" <<'EOF'
# prueba
ses_keep0000000000000000000001
EOF

echo "== dry-run"
out="$(run)"
assert_contains "$out" "A conservar           : 1" "cuenta 1 a conservar"
assert_contains "$out" "A borrar              : 3" "cuenta 3 a borrar"
assert_contains "$out" "MODO SIMULACION" "no borra sin --apply"

count() { python3 - "$DB" "$1" <<'PY'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
print(c.execute(f"SELECT count(*) FROM {sys.argv[2]}").fetchone()[0])
PY
}
assert_eq "4" "$(count session_v2)" "dry-run no modifica la DB"

echo "== --apply (modo estricto)"
run --apply --yes --no-backup >/dev/null
assert_eq "1" "$(count session_v2)" "sobrevive solo la sesion listada"
assert_eq "1" "$(count session)" "borra tambien de la tabla legada"
assert_eq "1" "$(count message)" "borra mensajes en cascada"
assert_eq "1" "$(count part)" "borra parts en cascada"
assert_eq "1" "$(count todo)" "borra todos en cascada"
assert_eq "1" "$(count session_message)" "borra session_message en cascada"

echo "== segunda ejecucion"
out="$(run --apply --yes --no-backup)"
assert_contains "$out" "Nada que borrar" "idempotente"

echo
echo "Resultado: $PASS ok, $FAIL fallos"
[ "$FAIL" -eq 0 ] || exit 1
