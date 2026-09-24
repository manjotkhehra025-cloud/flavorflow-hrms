#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════════════
# sandbox-restore.sh — ONE command to bring the dev sandbox back after sleep/restart.
# What it does:
#   1. postgres install (if wiped) + start (data dir lives in /home/user/pgdata → survives restarts!)
#   2. npm ci + prisma migrate deploy + seed + demo fixture (op1/op2 logins)
#   3. next start on :3000 (background; logs at /home/user/hrms/.next-server.log)
#
# Usage:   bash scripts/sandbox-restore.sh
# Safe to re-run any number of times.
# ════════════════════════════════════════════════════════════════════════════
set -u
cd "$(dirname "$0")/.."   # repo root
PG=17
PGDATA=/home/user/pgdata
LOG=/home/user/hrms/.next-server.log

say(){ echo "── $1"; }

# ── 1. postgres ──────────────────────────────────────────────────────────────
if [ ! -x /usr/lib/postgresql/$PG/bin/pg_ctl ]; then
  say "postgres install kar da (sabooti wipe si)…"
  sudo apt-get update -q >/dev/null 2>&1
  sudo apt-get install -y -q postgresql >/dev/null 2>&1 || sudo apt-get install -y -q postgresql
fi
PGBIN=/usr/lib/postgresql/$PG/bin

if ! PGPASSWORD=dev psql -h 127.0.0.1 -U dev -d hrms -tc "SELECT 1" >/dev/null 2>&1; then
  say "postgres start kar rahaa…"
  if [ ! -d "$PGDATA/base" ]; then
    say "fresh data dir bana rahaa ($PGDATA)"
    sudo -u postgres $PGBIN/pg_ctl initdb -D "$PGDATA" >/dev/null 2>&1 || sudo -u postgres $PGBIN/pg_ctl -D "$PGDATA" init >/dev/null 2>&1
  fi
  # postgres user must traverse /home/user (drwx------) to reach pgdata
  chmod o+x /home/user
  sudo chown -R postgres:postgres "$PGDATA" 2>/dev/null
  sudo -u postgres $PGBIN/pg_ctl -D "$PGDATA" -o "-p 5432 -c listen_addresses=127.0.0.1" -l /tmp/pg.log start >/dev/null || {
    sleep 2
    sudo -u postgres $PGBIN/pg_ctl -D "$PGDATA" -o "-p 5432 -c listen_addresses=127.0.0.1" -l /tmp/pg.log start
  }
  sleep 2
  sudo -u postgres psql -c "CREATE DATABASE hrms;" 2>/dev/null
  sudo -u postgres psql -c "CREATE USER dev WITH PASSWORD 'dev' SUPERUSER;" 2>/dev/null
  say "postgres ✓ (data hrms/pgdata 'ch — restart te bachi hovegi)"
else
  say "postgres pehlaan hi chal rahi ✓"
fi

# ── 2. node deps + prisma + seed ─────────────────────────────────────────────
if [ ! -x node_modules/.bin/next ]; then
  say "node_modules install kar rahaa (npm ci)…"
  npm ci --no-audit --no-fund 2>&1 | tail -1
fi

say "prisma migrate deploy…"
npx prisma migrate deploy 2>&1 | tail -1

say "seed + demo fixture…"
npm run db:seed >/dev/null 2>&1 && echo "  seed ✓ (admin@flavorflow.co.in / Admin@123)"
npx tsx scripts/_demo-fixture.ts 2>&1 | tail -1

# ── 3. build + server ────────────────────────────────────────────────────────
if [ ! -f .next/BUILD_ID ]; then
  say "production build kar rahaa (ik mint lagg sakda)…"
  npm run build 2>&1 | grep -E "Compiled|error" | tail -2
fi

say "server :3000 te chala rahaa…"
pkill -f "next start" 2>/dev/null
( nohup ./node_modules/.bin/next start -p 3000 >"$LOG" 2>&1 & )
sleep 4

say "smoke test…"
curl -s -o /dev/null -w "  login page → HTTP %{http_code}\n" localhost:3000/
curl -s -X POST localhost:3000/api/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"op1@test.in","password":"Test@1234"}' | grep -q token \
  && echo "  op1@test.in login → ✓ (Test@1234)"

echo ""
echo "✅ SAB TYAR — server :3000 te LIVE (kill hove taan fer bash scripts/sandbox-restore.sh)"
