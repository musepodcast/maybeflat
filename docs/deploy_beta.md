# Maybeflat Beta Launch

This beta launch setup keeps the public site on `https://maybeflat.com` while letting the API live on a separate host.

## Recommended Shape

- Frontend: Cloudflare Pages
- Public domain: `maybeflat.com` and optionally `www.maybeflat.com`
- Public app URL: `https://maybeflat.com`
- API host: any FastAPI-friendly host such as Render, Railway, Fly.io, or your own VM
- API proxy path on Pages: `/api/*`

The repo now includes a Pages Function at `functions/api/[[path]].js` that proxies `https://maybeflat.com/api/...` to your real backend origin. The Flutter web app will use `/api` automatically on non-local web builds unless you override it with `--dart-define=MAYBEFLAT_API_BASE_URL=...`.

## 1. Deploy The API First

Deploy `backend_api` to a host that can run:

```powershell
uvicorn app.main:app --host 0.0.0.0 --port 8002
```

Set these environment variables on the backend host:

```text
MAYBEFLAT_ALLOWED_ORIGINS=https://maybeflat.com,https://www.maybeflat.com
MAYBEFLAT_ALLOWED_ORIGIN_REGEX=^https:\/\/.*\.pages\.dev$
```

After deploy, confirm the health endpoint works:

```text
https://your-api-host.example.com/health
```

It should return:

```json
{"status":"ok"}
```

## 2. Create The Cloudflare Pages Project

Use Direct Upload for the beta. It avoids having to install Flutter inside the Cloudflare Pages build image.
Cloudflare's current Direct Upload flow cannot later be converted into Git integration, so treat this as the fast beta path rather than the final deployment pipeline.

From the repo root:

```powershell
npx wrangler login
cd app_flutter
flutter pub get
flutter build web --release --dart-define=MAYBEFLAT_API_BASE_URL=/api
cd ..
npx wrangler pages project create maybeflat
```

In the Cloudflare Pages project settings, add:

- `MAYBEFLAT_API_ORIGIN=https://your-api-host.example.com`

Then deploy:

```powershell
npx wrangler pages deploy app_flutter/build/web --project-name maybeflat
```

Because `wrangler.jsonc` points Pages at `app_flutter/build/web`, the Pages Functions in `functions/` will be included with the deploy.

## 3. Attach `maybeflat.com`

In Cloudflare Pages:

1. Open the `maybeflat` Pages project.
2. Go to `Custom domains`.
3. Add `maybeflat.com`.
4. Add `www.maybeflat.com` too if you want the redirect pair.

Since the domain is already on Cloudflare, Pages should create the needed DNS records for you after confirmation.

## 4. Final Beta Smoke Test

Check these URLs after DNS finishes updating:

- `https://maybeflat.com`
- `https://maybeflat.com/api/health`
- `https://maybeflat.com/api/map/scene?detail=mobile`

If the homepage loads but the map stays offline, the usual causes are:

- `MAYBEFLAT_API_ORIGIN` is missing or wrong in Cloudflare Pages
- the backend host is down
- the backend host is blocking the Cloudflare proxy request

## Local Development

The app still defaults to `http://127.0.0.1:8002` for local development.

You can also point a local or preview web build at a specific backend:

```powershell
flutter build web --dart-define=MAYBEFLAT_API_BASE_URL=https://your-api-host.example.com
```
