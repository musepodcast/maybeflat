#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "run this script with sudo."
  exit 1
fi

if ! command -v systemd-run >/dev/null 2>&1; then
  echo "systemd-run is required."
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw is required."
  exit 1
fi

ACTION="${1:-}"
WINDOW_MINUTES="${2:-10}"
UNIT_NAME="maybeflat-ufw-rollback"
UFW_BIN="$(command -v ufw)"

case "$ACTION" in
  arm)
    systemctl stop "${UNIT_NAME}.timer" "${UNIT_NAME}.service" >/dev/null 2>&1 || true
    systemctl reset-failed "${UNIT_NAME}.timer" "${UNIT_NAME}.service" >/dev/null 2>&1 || true
    systemd-run \
      --quiet \
      --unit "$UNIT_NAME" \
      --description "Disable UFW automatically if firewall rollout locks out SSH" \
      --on-active "${WINDOW_MINUTES}m" \
      "$UFW_BIN" --force disable
    echo "Rollback guard armed."
    echo "UFW will be disabled automatically in ${WINDOW_MINUTES} minute(s) unless you disarm it."
    systemctl status "${UNIT_NAME}.timer" --no-pager || true
    ;;
  disarm)
    systemctl stop "${UNIT_NAME}.timer" "${UNIT_NAME}.service" >/dev/null 2>&1 || true
    systemctl reset-failed "${UNIT_NAME}.timer" "${UNIT_NAME}.service" >/dev/null 2>&1 || true
    echo "Rollback guard disarmed."
    ;;
  status)
    systemctl status "${UNIT_NAME}.timer" --no-pager || true
    ;;
  *)
    echo "usage: sudo ./deploy/firewall/ufw_rollback_guard.sh <arm|disarm|status> [minutes]"
    echo "examples:"
    echo "  sudo ./deploy/firewall/ufw_rollback_guard.sh arm 10"
    echo "  sudo ./deploy/firewall/ufw_rollback_guard.sh disarm"
    echo "  sudo ./deploy/firewall/ufw_rollback_guard.sh status"
    exit 1
    ;;
esac
