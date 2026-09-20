#!/usr/bin/env bash
# Runs ON THE VPS after CI syncs a new build (called over SSH by CircleCI).
set -euo pipefail
cd /opt/hrms/app

# Apply DB migrations (prisma CLI installed globally by setup-vm.sh)
set -a; [ -f .env ] && . ./.env; set +a
prisma migrate deploy --schema=prisma/schema.prisma

# (Re)start the app
if pm2 describe hrms >/dev/null 2>&1; then
  pm2 restart hrms --update-env
else
  pm2 start scripts/start.sh --name hrms --interpreter bash
fi
pm2 save
echo "Deploy complete ✅"
