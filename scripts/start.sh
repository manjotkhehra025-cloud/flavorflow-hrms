#!/usr/bin/env bash
# Loads /opt/hrms/app/.env and starts the standalone Next.js server.
# Used by PM2 on the VPS:  pm2 start scripts/start.sh --name hrms --interpreter bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

export TZ="${TZ:-Asia/Kolkata}"
export NODE_ENV=production
export PORT="${PORT:-3000}"
export HOSTNAME="0.0.0.0"

exec node server.js
