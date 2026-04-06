# Home Self-Hosting On Windows With Cloudflare Tunnel

This path runs Maybeflat on your own Windows machine with Docker Desktop and exposes it through Cloudflare Tunnel.

## Why This Path

- no VPS required
- no router port forwards for `80`, `443`, or `22`
- no direct public origin IP exposure in normal operation
- Cloudflare stays in front of `maybeflat.com`

Cloudflare documents Tunnel as outbound-only and designed to avoid exposing a public IP or inbound ports.

## What Runs On Your PC

- Docker container for the FastAPI API
- Docker container for Caddy
- Docker container for `cloudflared`
- Flutter web build files served by Caddy

## Files For This Setup

- `docker-compose.home.yml`
- `Caddyfile.home`
- `.env.home.example`
- `deploy_home.ps1`
- `stop_home.ps1`

## Prerequisites

On your Windows machine:

- Docker Desktop installed and running
- Flutter installed and on `PATH`
- `maybeflat.com` already on Cloudflare
- your machine should not sleep while hosting the site

## 1. Create A Tunnel In Cloudflare

Cloudflare's current dashboard flow is:

1. Log in to Cloudflare Zero Trust.
2. Go to `Networks` -> `Connectors` -> `Cloudflare Tunnels`.
3. Select `Create a tunnel`.
4. Choose `Cloudflared`.
5. Name it something like `maybeflat-home`.
6. Save the tunnel.

After the tunnel is created:

1. Open the tunnel.
2. Go to the published application or public hostname section.
3. Add hostname `maybeflat.com`.
4. Set service type to `HTTP`.
5. Set the service URL to `http://caddy:80`.
6. Add another hostname `www.maybeflat.com` pointing to the same `http://caddy:80`.

Because this repo uses a Docker network, the `cloudflared` container can reach the `caddy` container by the service name `caddy`.

## 2. Get The Tunnel Token

Cloudflare's current token flow for remotely-managed tunnels is:

1. Open the tunnel in the dashboard.
2. Select `Add a replica`.
3. Copy the `cloudflared` installation command into a text editor.
4. Extract the token value from that command.

The token is the long `eyJ...` string.

## 3. Create The Local Env File

From PowerShell in the repo root:

```powershell
Copy-Item .env.home.example .env.home
```

Then edit `.env.home` and set:

```text
CLOUDFLARE_TUNNEL_TOKEN=your-real-token-here
```

## 4. Start The Stack

From PowerShell in the repo root:

```powershell
.\deploy_home.ps1
```

That script will:

1. build the Flutter web app with `MAYBEFLAT_API_BASE_URL=/api`
2. start the local Docker stack
3. expose Caddy only on `127.0.0.1:8080`
4. start `cloudflared` with your tunnel token
5. pre-render the shared tile pyramid through zoom `6` by default

If you want to backfill or extend the shared raster tile pyramid manually after deploy:

```powershell
docker compose -f docker-compose.home.yml --env-file .env.home exec api python generate_tiles.py --max-zoom 6
```

That fills the same shared tile tree Caddy serves directly at `/api/map/tiles/{edge_mode}/{z}/{x}/{y}.png`.
You can tune deploy-time pre-rendering with `MAYBEFLAT_PRERENDER_TILES`, `MAYBEFLAT_PRERENDER_MAX_ZOOM`, and `MAYBEFLAT_PRERENDER_EDGE_MODES` in `.env.home`.

## 5. Test Locally First

In PowerShell:

```powershell
Invoke-WebRequest http://127.0.0.1:8080
Invoke-RestMethod http://127.0.0.1:8080/api/health
docker compose -f docker-compose.home.yml --env-file .env.home ps
docker compose -f docker-compose.home.yml --env-file .env.home logs --tail=100
```

Expected:

- local homepage loads on `http://127.0.0.1:8080`
- API health returns `status = ok`
- all three containers are running

## 6. Test Public Access

After the tunnel shows healthy in Cloudflare:

```powershell
Invoke-WebRequest https://maybeflat.com
Invoke-RestMethod https://maybeflat.com/api/health
```

## Security Rules

For this home-hosting path:

- do not forward router port `22`
- do not forward router ports `80` or `443`
- keep the site proxied through Cloudflare
- avoid creating DNS-only records for your home origin

If you need remote shell access, use a private admin path such as Cloudflare Access for SSH or a VPN rather than exposing SSH publicly.

## Stop The Stack

```powershell
.\stop_home.ps1
```

## Limitations

- your PC must stay powered on
- your PC should not sleep
- your home connection becomes part of uptime
- this is acceptable for a beta, not ideal for long-term production
