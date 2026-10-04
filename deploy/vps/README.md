# Deploy the API on an Ubuntu/Debian VPS

This deploys the Python JSON API behind Nginx and HTTPS. It does not deploy a browser-based HRMS website or the Flutter APK. The API listens only on `127.0.0.1:8080`; Nginx forwards `/api/v1/*` to it. The provided Nginx snippet is intended to be added to the existing HTTPS virtual host for `hr.flavorflow.co.in`, so any existing website routes can remain unchanged.

## 1. Check DNS and install prerequisites

Make sure the DNS `A` record for `hr.flavorflow.co.in` points to the VPS public IP. Allow inbound ports 80 and 443 in the VPS/cloud firewall. Then install Python and Nginx:

```sh
sudo apt update
sudo apt install -y python3 nginx
```

Place this repository's files on the VPS at `/opt/flavorflow-hrms-api` (the service needs at least `backend/server.py` and `backend/schema.sql`). Keep the source owned by root and readable, but not writable, by the service account.

Create the unprivileged service account if it does not already exist:

```sh
getent passwd flavorflow >/dev/null || \
  sudo useradd --system --user-group --home-dir /nonexistent \
    --shell /usr/sbin/nologin flavorflow
```

## 2. Set production credentials before the first start

Create a root-only environment file:

```sh
sudoedit /etc/flavorflow-hrms.env
```

Add the following, replacing the example emails and every password with values for your deployment:

```ini
HRMS_HOST=127.0.0.1
HRMS_PORT=8080
HRMS_DB_PATH=/var/lib/flavorflow-hrms/hrms.sqlite3
HRMS_ADMIN_EMAIL=admin@flavorflow.co.in
HRMS_ADMIN_PASSWORD=REPLACE_WITH_A_UNIQUE_RANDOM_SECRET
HRMS_MANAGER_EMAIL=manager@flavorflow.co.in
HRMS_MANAGER_PASSWORD=REPLACE_WITH_A_DIFFERENT_RANDOM_SECRET
HRMS_EMPLOYEE_EMAIL=employee@flavorflow.co.in
HRMS_EMPLOYEE_PASSWORD=REPLACE_WITH_ANOTHER_RANDOM_SECRET
```

Generate separate secrets on the VPS with `openssl rand -hex 32`; do not put real secrets in Git or send them in chat. The app seeds these three accounts on a new database, so set all three passwords before the first start. Seed credentials are only used when the database has no users; changing this file later does not reset existing passwords.

Lock down the file:

```sh
sudo chown root:root /etc/flavorflow-hrms.env
sudo chmod 600 /etc/flavorflow-hrms.env
```

## 3. Start the API with systemd

Install the unit included in this repository and start it:

```sh
sudo install -m 0644 /opt/flavorflow-hrms-api/deploy/vps/flavorflow-hrms.service \
  /etc/systemd/system/flavorflow-hrms.service
sudo systemctl daemon-reload
sudo systemctl enable --now flavorflow-hrms
sudo systemctl status --no-pager flavorflow-hrms
```

The unit creates `/var/lib/flavorflow-hrms` for the SQLite database and runs the API as the unprivileged `flavorflow` user. Check the service locally before changing Nginx:

```sh
curl -i http://127.0.0.1:8080/api/v1/health
```

Expected response: HTTP 200 with JSON containing `"status":"ok"`. The API base `/api/v1` also returns a JSON status response.

## 4. Route the API through the existing Nginx HTTPS site

Install the location snippet:

```sh
sudo install -D -m 0644 /opt/flavorflow-hrms-api/deploy/vps/nginx-api-location.conf \
  /etc/nginx/snippets/flavorflow-hrms-api.conf
```

Find the Nginx `server` block whose `server_name` is `hr.flavorflow.co.in` and which handles HTTPS (usually `listen 443 ssl`). Add this line **inside that existing `server { ... }` block**:

```nginx
include snippets/flavorflow-hrms-api.conf;
```

This is important if the subdomain already serves a website: keep its existing `location /` and add the include alongside it. The more-specific `/api/v1/` location will forward API requests to Python instead of the website's 404 page. If there are separate HTTP and HTTPS server blocks, the include must be active in the HTTPS block; HTTP can continue redirecting to HTTPS.

Validate and reload Nginx:

```sh
sudo nginx -t
sudo systemctl reload nginx
```

If HTTPS is not set up yet, make sure DNS is pointing to this VPS and ports 80/443 are open, then install Certbot and request a certificate:

```sh
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d hr.flavorflow.co.in
```

If another proxy (Apache, Caddy, Docker, or a control-panel proxy) is in front of Nginx, configure that proxy to pass `/api/v1/*` through to Nginx as well.

## 5. Verify the public endpoint

```sh
curl -i https://hr.flavorflow.co.in/api/v1/health
```

It should return HTTP 200 JSON, not an HTML 404. The Android build's existing `API_BASE_URL` is `https://hr.flavorflow.co.in/api/v1/`, so no client URL change is needed when this domain is correct.

If the local health check works but the public URL still shows a website 404, the active HTTPS virtual host is not using the API snippet. Inspect the loaded configuration and service logs:

```sh
sudo nginx -T | grep -nE 'server_name|flavorflow-hrms-api|api/v1|proxy_pass'
sudo journalctl -u flavorflow-hrms -n 100 --no-pager
```

Do not expose port 8080 publicly; the systemd environment binds the API to loopback. Back up `/var/lib/flavorflow-hrms` regularly and keep the environment file and database private.
