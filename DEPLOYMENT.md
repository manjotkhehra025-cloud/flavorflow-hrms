# 🚀 Your Next Steps — Take FlavorFlow HRMS Live

Everything below is ordered. Do the steps top to bottom; each is copy-paste ready.
Total time: **~60–90 minutes** (most of it one-time setup).

---

## Step 0 — Push this code to GitHub (5 min)

```bash
cd hrms
git init
git add -A
git commit -m "Initial HRMS: core HR (employees, attendance, leave) v1"
```

Create a repo on GitHub named **`flavorflow-hrms`** (private recommended), then:

```bash
git remote add origin git@github.com:<your-username>/flavorflow-hrms.git
git branch -M main
git push -u origin main
```

---

## Step 1 — Create the GCP VPS (10 min)

1. GCP Console → **Compute Engine → VM instances → Create instance**
   - Name: `hrms-prod`
   - Region: `asia-south1` (Mumbai) — closest to Amritsar
   - Machine: **e2-small** (2 GB RAM, ~₹1,200/mo). *e2-micro works but is tight.*
   - Boot disk: **Ubuntu 24.04 LTS**, 30 GB standard
   - Firewall: ✅ Allow HTTP traffic, ✅ Allow HTTPS traffic
2. After it's created, click the VM → **Edit** → Network interfaces → External IPv4
   → **Reserve a static IP** (name it `hrms-ip`). Write the IP down — call it `VPS_IP`.
   *(Static IP is free while attached to a running VM.)*

---

## Step 2 — Point the domain (5 min + wait)

Wherever `flavorflow.co.in` DNS is managed (registrar / Cloudflare), add:

| Type | Host/Name | Value        | TTL |
| ---- | --------- | ------------ | --- |
| A    | `hr`      | your `VPS_IP`| 300 |

Check with: `nslookup hr.flavorflow.co.in` — proceed when it returns your VPS_IP.

---

## Step 3 — One-time server setup (15 min)

SSH into the VM (GCP Console → the VM → **SSH** button in browser). Then:

```bash
git clone https://github.com/<your-username>/flavorflow-hrms.git
cd flavorflow-hrms
sudo bash scripts/setup-vm.sh
```

It installs Node 22, PM2, PostgreSQL, Nginx; creates the DB; writes `/opt/hrms/app/.env`
with auto-generated secrets. **Save the output somewhere safe.**

---

## Step 4 — Nginx + free SSL (10 min)

Still on the VM:

```bash
sudo cp deploy/nginx-hrms.conf /etc/nginx/sites-available/hrms
sudo ln -s /etc/nginx/sites-available/hrms /etc/nginx/sites-enabled/hrms
sudo nginx -t && sudo systemctl reload nginx

sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d hr.flavorflow.co.in     # free Let's Encrypt cert, auto-renews
```

---

## Step 5 — Give CircleCI deploy access (10 min)

On your **local machine**:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/hrms_deploy -N ""        # dedicated deploy key
ssh-copy-id -i ~/.ssh/hrms_deploy.pub <VPS_USER>@<VPS_IP> # VPS_USER = your gcloud SSH username
```

Then in **CircleCI** (you already connected the GitHub repo):

1. Project → **Project Settings → SSH Keys → Additional SSH Keys → Add SSH Key**
   - Hostname: `VPS_IP` · Private key: contents of `~/.ssh/hrms_deploy`
2. **Project Settings → Environment Variables**, add:
   - `VPS_HOST` = your `VPS_IP`
   - `VPS_USER` = your VM SSH username

> The VM user needs passwordless sudo for the deploy step. On GCP VMs the
> default user already has it. If you created a custom user:
> `echo 'USERNAME ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/deploy`

---

## Step 6 — Ship it 🎉 (2 min)

```bash
git commit -am "Setup CI deploy" ; git push
```

Watch CircleCI: **build → deploy** turns green. Then open:

- **https://hr.flavorflow.co.in/setup** → create your company + admin (runs once)
- **https://hr.flavorflow.co.in** → log in → add departments, employees, holidays

---

## Daily ops cheat-sheet (on the VM)

| Task                  | Command                                |
| --------------------- | -------------------------------------- |
| App logs              | `pm2 logs hrms`                        |
| Restart app           | `pm2 restart hrms`                     |
| App status            | `pm2 status`                           |
| Nginx logs            | `sudo tail -f /var/log/nginx/error.log`|
| Backup DB (do weekly) | `pg_dump -U hrms hrms > backup-$(date +%F).sql` |

---

## Roadmap after v1 is stable

1. **Payroll** (salary structure, payslips, PF/ESI/TDS) — biggest v2 module
2. **Premium Android app** — the API is already live; login returns a Bearer token.
   Recommend Flutter (one codebase → Android + iOS later) or native Kotlin.
3. **SaaS conversion** — company sign-up flow + subscription billing; schema already
   carries `companyId` everywhere, so this is an additive project.
