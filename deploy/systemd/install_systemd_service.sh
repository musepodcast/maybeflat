#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "run this installer with sudo."
  exit 1
fi

DEPLOY_PATH="${1:-/opt/maybeflat}"
DEPLOY_USER="${2:-${SUDO_USER:-}}"

if [[ -z "$DEPLOY_USER" ]]; then
  echo "usage: sudo ./deploy/systemd/install_systemd_service.sh /absolute/deploy/path deployuser"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_PATH="$SCRIPT_DIR/maybeflat.service"
TARGET_PATH="/etc/systemd/system/maybeflat.service"

sed \
  -e "s|__DEPLOY_PATH__|$DEPLOY_PATH|g" \
  -e "s|__DEPLOY_USER__|$DEPLOY_USER|g" \
  "$TEMPLATE_PATH" > "$TARGET_PATH"

systemctl daemon-reload
systemctl enable maybeflat.service
systemctl restart maybeflat.service
systemctl status maybeflat.service --no-pager
