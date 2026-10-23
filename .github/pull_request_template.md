## Qué cambia

<!-- Resumen breve del cambio. -->

## Por qué

<!-- Problema que resuelve o motivación. -->

## Cómo probarlo

```bash
./tests/run-tests.sh
```

## Checklist

- [ ] `bash -n cleanup-sessions.sh tests/run-tests.sh`
- [ ] `shellcheck -S warning cleanup-sessions.sh tests/run-tests.sh`
- [ ] `./tests/run-tests.sh` pasa
- [ ] No incluyo datos personales (IDs de sesión, rutas, títulos)
- [ ] Actualicé README/CHANGELOG si aplica
