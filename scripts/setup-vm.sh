#!/usr/bin/env bash
# =============================================================================
# FlavorFlow HRMS — one-time VPS setup (Ubuntu 24.04 on GCP Compute Engine)
#
# Run ON THE SERVER (as a sudo user), e.g.:
#   curl -sSL https://raw.githubusercontent.com/<you>/flavorflow-hrms/main/scripts/setup-vm.sh | sudo bash
# or after cloning the repo:  sudo bash scripts/setup-vm.sh
#
# Installs: Node.js 22, PM2, Prisma CLI, PostgreSQL 16, Nginx (+ UFW rules)
# Creates:  database + db user, /opt/hrms/app with a generated .env
# After this: point DNS, run certbot (see DEPLOYMENT.md), deploy from CircleCI.
# =============================================================================
set -euo pipefail

DB_NAME="hrms"
DB_USER="hrms"
APP_DIR="/opt/hrms/app"

if [ "$EUID" -ne 0 ]; then echo "Run with sudo."; exit 1; fi

echo "==> System packages"
apt-get update -y
apt-get install -y curl ca-certificates gnupg ufw nginx postgresql postgresql-contrib rsync unzip

echo "==> Node.js 22"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs
fi

echo "==> Global Node tools"
npm install -g pm2 prisma >/dev/null

echo "==> Firewall (allow OpenSSH + HTTP/S)"
ufw allow OpenSSH >/dev/null || true
ufw allow 'Nginx Full' >/dev/null || true
ufw --force enable >/dev/null || true

echo "==> PostgreSQL database & user"
DB_PASS="$(openssl rand -hex 16)"
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" | grep -q 1 \
  || sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASS}';"
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1 \
  || sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"

echo "==> App directory & env"
mkdir -p "${APP_DIR}/scripts"
AUTH_SECRET="$(openssl rand -base64 32)"
if [ ! -f "${APP_DIR}/.env" ]; then
  cat > "${APP_DIR}/.env" <<EOF
DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@localhost:5432/${DB_NAME}"
AUTH_SECRET="${AUTH_SECRET}"
PORT=3000
TZ=Asia/Kolkata
EOF
  chmod 600 "${APP_DIR}/.env"
  echo "    .env written to ${APP_DIR}/.env (DB password auto-generated)"
else
  echo "    .env already exists — keeping it"
fi

echo "==> PM2 startup on boot"
pm2 startup systemd -u root --hp /root >/dev/null || true

cat <<'DONE'

✅ Server setup complete.

NEXT STEPS (see DEPLOYMENT.md for details):
  1. DNS: add an A record  hr.flavorflow.co.in → this server's static external IP
  2. SSL: sudo certbot --nginx -d hr.flavorflow.co.in   (after DNS propagates)
  3. Nginx: copy deploy/nginx-hrms.conf to /etc/nginx/sites-available/ and enable it
  4. In CircleCI project settings: add VPS_HOST, VPS_USER, and the deploy SSH key
  5. Push to main → CircleCI builds & deploys → open https://hr.flavorflow.co.in/setup
DONE
