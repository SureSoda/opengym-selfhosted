#!/usr/bin/env bash
# Actualiza este repo y las imágenes, con un respaldo antes por las dudas.
#   sudo ./scripts/update.sh
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/backup.sh
git pull --ff-only
docker compose pull -q
docker compose up -d
docker image prune -f >/dev/null
docker compose ps
