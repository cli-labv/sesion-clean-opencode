# Seguridad

## Reportar una vulnerabilidad

No abras un issue público. Usa **Security → Report a vulnerability** en GitHub
(Private Vulnerability Reporting) o contacta al mantenedor por correo.

Incluye: versión de opencode, versión de bash/python, sistema operativo y una
descripción del impacto. Si puedes, un ejemplo con una DB ficticia.

## Alcance

Este script **borra datos de forma irreversible**. Los puntos clave:

- Sin `--apply` nunca modifica la DB.
- `--apply` crea un backup con la API de backup de SQLite salvo que uses
  `--no-backup`.
- `--vacuum` puede fallar si opencode está abierto; no corrompe la DB.

Si encuentras una forma de que el script borre datos sin `--apply`, o de que
borre sesiones de la lista blanca, es un problema de seguridad: repórtalo en
privado.
