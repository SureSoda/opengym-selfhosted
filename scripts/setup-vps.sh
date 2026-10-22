#!/usr/bin/env bash
# Prepara un VPS Ubuntu/Debian recién creado y levanta openGym.
#   sudo ./scripts/setup-vps.sh
#
# Idempotente: se puede volver a correr sin romper nada.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

log() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "correr con sudo"
# shellcheck source=/dev/null
[ -f /etc/os-release ] && . /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die "pensado para Ubuntu o Debian (encontré: ${ID:-desconocido})" ;; esac

# ── .env ────────────────────────────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  chmod 600 .env
  die "creé .env a partir de .env.example: completá DOMAIN y ACME_EMAIL y volvé a correr el script"
fi
set -a
# shellcheck source=/dev/null
. ./.env
set +a
case "${DOMAIN:-}" in ""|gym.example.com) die "falta DOMAIN en .env" ;; esac
case "${ACME_EMAIL:-}" in ""|you@example.com) die "falta ACME_EMAIL en .env" ;; esac

# ── Paquetes base y actualizaciones automáticas de seguridad ───────────────
log "Instalando paquetes base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg ufw unattended-upgrades dnsutils >/dev/null
dpkg-reconfigure -f noninteractive unattended-upgrades

# ── Docker (repositorio oficial) ───────────────────────────────────────────
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  log "Instalando Docker"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
fi
systemctl enable --now docker >/dev/null

# ── Firewall: solo SSH, HTTP y HTTPS ───────────────────────────────────────
# Ojo: Docker publica sus puertos por fuera de ufw, pero acá el único contenedor con puertos
# es Caddy (80/443), que son justamente los que queremos abiertos.
log "Configurando firewall"
ufw allow OpenSSH >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 443/udp >/dev/null
ufw --force enable >/dev/null

# ── DNS: Let's Encrypt falla si el dominio todavía no apunta a este servidor ─
MY_IP="$(curl -fsS4 https://api.ipify.org || true)"
DNS_IP="$(dig +short A "$DOMAIN" | tail -n1)"
if [ -n "$MY_IP" ] && [ "$DNS_IP" != "$MY_IP" ]; then
  printf '\033[1;33maviso:\033[0m %s resuelve a "%s" pero este servidor es %s.\n' "$DOMAIN" "${DNS_IP:-nada}" "$MY_IP"
  printf '       Caddy va a reintentar el certificado solo cuando el DNS se actualice.\n'
fi

# ── openGym ────────────────────────────────────────────────────────────────
log "Levantando openGym"
mkdir -p data backups
chmod 700 data backups
docker compose pull -q
docker compose up -d

# ── Respaldo diario a las 04:00 ────────────────────────────────────────────
log "Programando respaldo diario"
CRON_LINE="0 4 * * * root $ROOT/scripts/backup.sh >> /var/log/opengym-backup.log 2>&1"
echo "$CRON_LINE" > /etc/cron.d/opengym-backup
chmod 644 /etc/cron.d/opengym-backup

log "Listo: https://$DOMAIN"
echo "Creá tu perfil ahora (el primero queda como admin) y después activá INVITE_ONLY=1 en .env"
echo "y aplicalo con: docker compose up -d"
