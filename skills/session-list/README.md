# Skill: session-list

Lista sesiones desde `session_v2` de opencode ordenadas cronológicamente (más antiguo → más reciente).

## Funciones
- `session_list_get_tsv <db>` - Retorna TSV completo
- `session_list_roots <tsv>` - Filtra solo sesiones raíz
- `session_list_format_brief <tsv>` - Formato `fecha | id | nombre`

## Dependencias
- bash, python3, sqlite3
