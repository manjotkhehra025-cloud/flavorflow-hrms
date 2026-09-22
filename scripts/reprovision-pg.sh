#!/usr/bin/env bash
# Reprovision local sandbox PG after a sandbox restart (apt installs are wiped between sessions).
set -e
if ! ls /usr/lib/postgresql/*/bin/postgres > /dev/null 2>&1; then
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-client > /tmp/pg-install.log 2>&1
fi
sudo pg_ctlcluster 17 main start 2>/dev/null || true
sleep 2
sudo -u postgres psql -qc "DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='dev') THEN CREATE USER dev WITH PASSWORD 'dev' SUPERUSER; END IF; END \$\$;"
sudo -u postgres psql -qc "SELECT 1 FROM pg_database WHERE datname='hrms'" | grep -q 1 || sudo -u postgres createdb -O dev hrms
cd "$(dirname "$0")/.."
npx prisma@6.5.0 migrate deploy | tail -1
npx prisma@6.5.0 generate > /dev/null 2>&1 || true
echo "PG ready ✅"
