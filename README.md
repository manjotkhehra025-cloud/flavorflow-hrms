# FlavorFlow HRMS

Core HR for FlavorFlow — employees, departments, attendance and leave — with an
API-first design so the future Android app plugs into the same backend.

**Live domain:** https://hr.flavorflow.co.in

## Stack

| Layer     | Choice                                   |
| --------- | ---------------------------------------- |
| App       | Next.js 15 (App Router) + TypeScript     |
| Styling   | Tailwind CSS v4                          |
| DB / ORM  | PostgreSQL 16 + Prisma 6                 |
| Auth      | Email + password → JWT (httpOnly cookie; Bearer token for mobile API) |
| CI/CD     | GitHub → CircleCI → rsync+SSH → GCP VPS  |
| Server    | Nginx reverse proxy + PM2, SSL via Certbot |

## Features (v1 — Core HR)

- 🔐 **Auth & roles** — ADMIN / HR / EMPLOYEE, one-time `/setup` bootstrap
- 👥 **Employees** — directory, profiles, codes (FF-001…), optional login accounts
- 🏢 **Departments & designations**
- ⏰ **Attendance** — self check-in/check-out, daily company view for HR
- 🌴 **Leaves** — apply, approve/reject, balances by leave type
- 📅 **Holiday calendar**
- 📡 **JSON API** (`/api/auth/login`, `/api/attendance`, `/api/leaves`) — Android-ready

Multi-tenant-ready: every table carries `companyId`, so a future SaaS version is
an additive change rather than a rewrite.

## Local development

```bash
cp .env.example .env          # defaults match the compose file below
docker compose up -d db       # PostgreSQL 16 on :5432
npm install
npx prisma migrate deploy     # create tables
npm run db:seed               # optional demo admin (admin@flavorflow.co.in / Admin@123)
npm run dev                   # http://localhost:3000
```

Without seed data, open http://localhost:3000/setup once to create your company + admin.

## Deployment

See **[DEPLOYMENT.md](./DEPLOYMENT.md)** — step-by-step: GCP VM → DNS → Nginx/SSL
→ GitHub → CircleCI → first login.

## Project layout

```
prisma/            schema + migrations + seed
src/
  actions/         server actions (all business logic)
  app/(app)/       authenticated UI (dashboard, employees, …)
  app/api/         JSON API (token auth — future Android app)
  app/login|setup/ public pages
  components/      sidebar, UI primitives
  lib/             db, auth (JWT/session), helpers
scripts/           start.sh, post-deploy.sh, setup-vm.sh
deploy/            nginx vhost
.circleci/         CI pipeline
```
