#!/usr/bin/env bash
# Restaura un respaldo hecho con backup.sh.
#   sudo ./scripts/restore.sh backups/opengym-2026-01-31_0400.tar.gz
#
# El ./data actual no se borra: se mueve a data.antes-de-restaurar-<fecha>.
set -euo pipefail

ARCHIVE="${1:?uso: restore.sh <archivo .tar.gz>}"
ARCHIVE="$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")"
cd "$(dirname "$0")/.."

[ -f "$ARCHIVE" ] || { echo "no existe: $ARCHIVE" >&2; exit 1; }
# El listado va a una variable: con pipefail, `tar | grep -q` puede fallar por SIGPIPE en
# archivos grandes aunque el respaldo sea válido.
LISTING="$(tar tzf "$ARCHIVE")"
grep -qx 'data/secret' <<<"$LISTING" || { echo "$ARCHIVE no parece un respaldo de openGym" >&2; exit 1; }

docker compose stop api
if [ -d data ]; then
  ASIDE="data.antes-de-restaurar-$(date +%F_%H%M%S)"
  mv data "$ASIDE"
  echo "datos actuales movidos a $ASIDE"
fi
tar xzf "$ARCHIVE"
docker compose up -d
echo "restaurado desde $ARCHIVE"
