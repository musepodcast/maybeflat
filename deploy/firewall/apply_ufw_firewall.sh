#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "run this script with sudo."
  exit 1
fi

if [[ "$#" -lt 1 ]]; then
  echo "usage: sudo ./deploy/firewall/apply_ufw_firewall.sh <ssh-cidr> [additional-ssh-cidr...]"
  echo "example: sudo ./deploy/firewall/apply_ufw_firewall.sh 198.51.100.24/32 2001:db8::5/128"
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "ufw is required on Ubuntu. Install it first with: sudo apt-get install -y ufw"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to fetch the current Cloudflare IP ranges."
  exit 1
fi

SSH_PORT="${SSH_PORT:-22}"
SSH_CIDRS=("$@")

readarray -t CLOUDFLARE_IPV4 < <(curl -fsSL https://www.cloudflare.com/ips-v4)
readarray -t CLOUDFLARE_IPV6 < <(curl -fsSL https://www.cloudflare.com/ips-v6)

if [[ "${#CLOUDFLARE_IPV4[@]}" -eq 0 || "${#CLOUDFLARE_IPV6[@]}" -eq 0 ]]; then
  echo "failed to fetch Cloudflare IP ranges."
  exit 1
fi

echo "Applying UFW rules for SSH and Cloudflare-origin HTTP/HTTPS traffic."
echo "SSH port: ${SSH_PORT}"
printf 'Allowed SSH CIDRs:\n'
printf '  %s\n' "${SSH_CIDRS[@]}"

ufw default deny incoming
ufw default allow outgoing

for cidr in "${SSH_CIDRS[@]}"; do
  ufw allow proto tcp from "$cidr" to any port "$SSH_PORT" comment "maybeflat ssh"
done

for cidr in "${CLOUDFLARE_IPV4[@]}"; do
  [[ -n "$cidr" ]] || continue
  ufw allow proto tcp from "$cidr" to any port 80 comment "cf http"
  ufw allow proto tcp from "$cidr" to any port 443 comment "cf https"
done

for cidr in "${CLOUDFLARE_IPV6[@]}"; do
  [[ -n "$cidr" ]] || continue
  ufw allow proto tcp from "$cidr" to any port 80 comment "cf http"
  ufw allow proto tcp from "$cidr" to any port 443 comment "cf https"
done

ufw --force enable
ufw status verbose
