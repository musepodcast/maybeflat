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

mkdir -p var/log/caddy

pushd app_flutter >/dev/null
flutter pub get
flutter build web --release --dart-define=MAYBEFLAT_API_BASE_URL=/api
popd >/dev/null

"${DOCKER_COMPOSE[@]}" --env-file .env.production up -d --build --remove-orphans
"${DOCKER_COMPOSE[@]}" --env-file .env.production ps
