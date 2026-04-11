# Self-Hosted Production

This production path runs the whole site on one VPS:

- `Caddy` serves `https://maybeflat.com`
- the Flutter web build is served as static files
- `/api/*` is reverse-proxied to the FastAPI container
- `Postgres` runs privately on the Docker network for analytics and future app data
- Cloudflare remains your DNS and edge proxy

## Production Layout

```text
Internet
  -> Cloudflare DNS / proxy
  -> VPS
     -> Caddy container
        -> static Flutter web files at /
        -> reverse proxy /api/* to api:8002
     -> FastAPI container
        -> Postgres container
```

## Files Added For This Setup

- `backend_api/Dockerfile`
- `docker-compose.yml`
- `Caddyfile`
- `.env.production.example`
- `deploy_production.sh`
- `deploy/systemd/maybeflat.service`
- `deploy/firewall/apply_ufw_firewall.sh`
- `deploy/firewall/preflight_ssh_access.sh`
- `deploy/firewall/ufw_rollback_guard.sh`
- `deploy/bootstrap/first_boot.sh`

## VPS Requirements

- Ubuntu 22.04 or 24.04 is a good default
- Docker Engine installed
- Docker Compose available
- Flutter installed on the VPS if you want the deploy script to build the web app there
- The deploy user should be in the `docker` group

Ports that must be open:

- `80/tcp`
- `443/tcp`

## First-Time Setup

If this is a fresh Ubuntu VPS, start with [docs/first_boot.md](first_boot.md).

1. Copy the repo onto the VPS.
2. Copy `.env.production.example` to `.env.production`.
3. Set `ACME_EMAIL` in `.env.production`.
4. Set a strong `MAYBEFLAT_POSTGRES_PASSWORD` in `.env.production`.
5. Set a long random `MAYBEFLAT_ADMIN_TOKEN` in `.env.production`.
6. Point Cloudflare DNS for `maybeflat.com` to the VPS public IP.
7. Set Cloudflare SSL mode to `Full` or `Full (strict)`.

## Deploy

Run from the repo root on the VPS:

```bash
chmod +x deploy_production.sh
./deploy_production.sh
```

That script will:

1. build the Flutter web app with `MAYBEFLAT_API_BASE_URL=/api`
2. build the FastAPI image
3. start or update the Docker Compose stack
4. pre-render the shared tile pyramid through zoom `6` by default

You can tune deploy-time pre-rendering with `MAYBEFLAT_PRERENDER_TILES`, `MAYBEFLAT_PRERENDER_MAX_ZOOM`, and `MAYBEFLAT_PRERENDER_EDGE_MODES` in `.env.production`.

## Auto-Start After Reboot

Install the included systemd unit after the first successful deploy:

```bash
chmod +x deploy/systemd/install_systemd_service.sh
sudo ./deploy/systemd/install_systemd_service.sh /absolute/path/to/maybeflat your-linux-user
```

That installs `/etc/systemd/system/maybeflat.service`, reloads systemd, enables the service, and starts it.

Useful commands:

```bash
sudo systemctl status maybeflat
sudo systemctl restart maybeflat
sudo journalctl -u maybeflat -n 100 --no-pager
```

## Firewall Lockdown

For Ubuntu `ufw` rules that only allow `80/443` from Cloudflare and only allow SSH from your own IP ranges, see [docs/ubuntu_firewall.md](ubuntu_firewall.md).

Quick example:

From your admin machine:

```bash
chmod +x deploy/firewall/preflight_ssh_access.sh
./deploy/firewall/preflight_ssh_access.sh your-linux-user maybeflat.com 22
```

Then on the VPS:

```bash
chmod +x deploy/firewall/apply_ufw_firewall.sh
chmod +x deploy/firewall/ufw_rollback_guard.sh
sudo ./deploy/firewall/ufw_rollback_guard.sh arm 10
sudo ./deploy/firewall/apply_ufw_firewall.sh 198.51.100.24/32
```

Replace `198.51.100.24/32` with your real public admin IP or CIDR.

## How Requests Flow

- `https://maybeflat.com` -> Caddy serves files from `app_flutter/build/web`
- `https://maybeflat.com/api/health` -> Caddy proxies to `api:8002/health`
- `https://maybeflat.com/api/map/...` -> Caddy proxies to the FastAPI container
- the FastAPI container reaches Postgres internally at `postgres:5432`

The API and Postgres containers are not exposed directly to the internet. Only Caddy publishes ports.

## Admin Analytics

After deploy, open `https://maybeflat.com/admin`.

That dashboard reads the protected admin analytics endpoint and requires the `MAYBEFLAT_ADMIN_TOKEN` you set in `.env.production`.

## Updating Production

After pulling new code on the VPS:

```bash
git pull
./deploy_production.sh
```

To backfill or extend the shared raster tile pyramid manually after deploy:

```bash
docker compose exec api python generate_tiles.py --max-zoom 6
```

That fills the same shared tile tree Caddy serves directly at `/api/map/tiles/{edge_mode}/{z}/{x}/{y}.png`.

The repo is currently set up for manual production deploys. If you later move back to a VPS auto-deploy flow, add a GitHub Actions workflow that SSHes to the host and runs `./deploy_production.sh`.

## Notes

- The current deploy script builds Flutter on the VPS. If you prefer, you can build `app_flutter/build/web` in CI or locally and ship only the built assets to the server.
- Caddy handles SPA routing by rewriting unknown paths to `index.html`.
- The backend image copies `docs/data` into the container because the API loads those datasets at runtime.
- Caddy now trusts Cloudflare proxy headers using Cloudflare's published IP ranges and writes JSON access logs to `var/log/caddy/maybeflat-access.log`.
- For stronger origin protection, restrict inbound `80/443` at the VPS firewall to Cloudflare IP ranges and keep SSH limited to your own IPs.
