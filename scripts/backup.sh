#!/usr/bin/env bash
# Respalda ./data en ./backups/opengym-<fecha>.tar.gz y borra los que superan BACKUP_KEEP_DAYS.
# Con BACKUP_RCLONE_REMOTE definido, además copia el archivo fuera del VPS.
#
# No hace falta detener la API: openGym escribe cada archivo en uno temporal y lo renombra,
# así que el tar nunca ve un JSON escrito a medias.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ -f .env ]; then
  set -a
  # shellcheck source=/dev/null
  . ./.env
  set +a
fi
KEEP_DAYS="${BACKUP_KEEP_DAYS:-14}"

mkdir -p backups
chmod 700 backups
umask 077   # el archivo trae passkeys públicas, sesiones firmadas y todo el historial

ARCHIVE="backups/opengym-$(date +%F_%H%M).tar.gz"
tar czf "$ARCHIVE" data/
echo "$(date '+%F %T') respaldo creado: $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

find backups -name 'opengym-*.tar.gz' -mtime +"$KEEP_DAYS" -print -delete

if [ -n "${BACKUP_RCLONE_REMOTE:-}" ]; then
  command -v rclone >/dev/null || { echo "BACKUP_RCLONE_REMOTE está definido pero rclone no está instalado" >&2; exit 1; }
  rclone copy "$ARCHIVE" "$BACKUP_RCLONE_REMOTE"
  echo "$(date '+%F %T') copiado a $BACKUP_RCLONE_REMOTE"
fi
