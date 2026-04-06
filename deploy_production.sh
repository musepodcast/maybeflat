#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required on the VPS to build the web client."
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required on the VPS."
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker-compose)
else
  echo "docker compose is required on the VPS."
  exit 1
fi

if [[ ! -f .env.production ]]; then
  echo "missing .env.production. Copy .env.production.example and fill it in first."
  exit 1
fi

get_config_value() {
  local key="$1"
  local path="$2"
  awk -F= -v target="$key" '$1 == target {sub(/^[[:space:]]+/, "", $2); print $2; exit}' "$path"
}

mkdir -p var/log/caddy

pushd app_flutter >/dev/null
flutter pub get
flutter build web --release --dart-define=MAYBEFLAT_API_BASE_URL=/api
popd >/dev/null

"${DOCKER_COMPOSE[@]}" --env-file .env.production up -d --build --remove-orphans
"${DOCKER_COMPOSE[@]}" --env-file .env.production ps

PRERENDER_TILES="$(get_config_value MAYBEFLAT_PRERENDER_TILES .env.production || true)"
if [[ -z "${PRERENDER_TILES}" ]]; then
  PRERENDER_TILES="1"
fi

if [[ ! "${PRERENDER_TILES}" =~ ^(0|false|FALSE|False|no|NO|No)$ ]]; then
  PRERENDER_MAX_ZOOM="$(get_config_value MAYBEFLAT_PRERENDER_MAX_ZOOM .env.production || true)"
  if [[ -z "${PRERENDER_MAX_ZOOM}" ]]; then
    PRERENDER_MAX_ZOOM="6"
  fi

  PRERENDER_EDGE_MODES="$(get_config_value MAYBEFLAT_PRERENDER_EDGE_MODES .env.production || true)"
  if [[ -z "${PRERENDER_EDGE_MODES}" ]]; then
    PRERENDER_EDGE_MODES="coastline,country,both"
  fi

  echo "Pre-rendering shared tile pyramid (max zoom ${PRERENDER_MAX_ZOOM}, edge modes ${PRERENDER_EDGE_MODES})..."
  "${DOCKER_COMPOSE[@]}" --env-file .env.production exec -T api \
    python generate_tiles.py --max-zoom "${PRERENDER_MAX_ZOOM}" --edge-modes "${PRERENDER_EDGE_MODES}"
fi

echo
echo "Production stack started."
echo "Local check: https://127.0.0.1"
