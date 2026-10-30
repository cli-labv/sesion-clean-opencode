# Contribuir

Gracias por tomarte el tiempo de aportar.

## Antes de abrir un issue

- Revisa que no exista uno igual.
- **No publiques** IDs de sesión, títulos, rutas ni fragmentos de tu base de datos.
  Usa datos ficticios si necesitas un ejemplo.

## Cambios de código

1. Haz un fork y crea una rama: `git checkout -b fix/mi-cambio`.
2. Modifica lo mínimo necesario; mantén el estilo del script (bash POSIX-ish +
   helpers `python3`, mensajes en español).
3. No cambies el comportamiento por defecto destructivo: sin `--apply` debe ser
   siempre simulación.
4. Prueba:

   ```bash
   make check
   ```

   Equivale a `bash -n`, `shellcheck -S warning` y `./tests/run-tests.sh`.

5. Abre un Pull Request describiendo qué cambia y cómo lo probaste.

## Tests

`tests/run-tests.sh` crea una DB SQLite de ejemplo en un directorio temporal y un
`opencode` falso en el `PATH`. Nunca toca tu base real. Si añades una opción,
añade su test ahí.

## Licencia

Al contribuir aceptas que tu aporte se publique bajo la licencia MIT del repo.
