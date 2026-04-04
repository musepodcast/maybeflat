#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 || "$#" -gt 3 ]]; then
  echo "usage: ./deploy/firewall/preflight_ssh_access.sh <deploy-user> <deploy-host> [ssh-port]"
  echo "example: ./deploy/firewall/preflight_ssh_access.sh isaac maybeflat.com 22"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required."
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "ssh is required."
  exit 1
fi

DEPLOY_USER="$1"
DEPLOY_HOST="$2"
SSH_PORT="${3:-22}"
SSH_TARGET="${DEPLOY_USER}@${DEPLOY_HOST}"

get_public_ip() {
  local endpoints=(
    "https://api.ipify.org"
    "https://ifconfig.me/ip"
    "https://icanhazip.com"
  )

  local endpoint
  local candidate
  for endpoint in "${endpoints[@]}"; do
    candidate="$(curl -fsSL --max-time 5 "$endpoint" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$candidate" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      printf '%s' "$candidate"
      return 0
    fi
    if [[ "$candidate" == *:* ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

PUBLIC_IP="$(get_public_ip || true)"

if [[ -z "$PUBLIC_IP" ]]; then
  echo "could not determine your current public IP."
  echo "check it manually before applying the firewall."
  exit 1
fi

if [[ "$PUBLIC_IP" == *:* ]]; then
  SSH_CIDR="${PUBLIC_IP}/128"
else
  SSH_CIDR="${PUBLIC_IP}/32"
fi

echo "Detected current public IP: $PUBLIC_IP"
echo "Suggested SSH CIDR:        $SSH_CIDR"
echo
echo "Testing SSH access to $SSH_TARGET on port $SSH_PORT..."

ssh -p "$SSH_PORT" \
  -o ConnectTimeout=8 \
  -o ServerAliveInterval=5 \
  -o ServerAliveCountMax=1 \
  "$SSH_TARGET" \
  "printf 'Connected to '; hostname; printf ' as '; whoami; printf '\n'; command -v ufw >/dev/null && echo 'ufw: installed' || echo 'ufw: missing'; command -v curl >/dev/null && echo 'curl: installed' || echo 'curl: missing'"

echo
echo "If that SSH test succeeded, you can use:"
echo "  sudo ./deploy/firewall/apply_ufw_firewall.sh $SSH_CIDR"
echo
echo "For extra safety on the VPS, arm the rollback guard first:"
echo "  sudo ./deploy/firewall/ufw_rollback_guard.sh arm 10"
