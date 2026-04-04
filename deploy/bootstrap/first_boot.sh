#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "run this script with sudo."
  exit 1
fi

DEPLOY_USER=""
INSTALL_FLUTTER_PREREQS=1
FORCE_DOCKER_REPLACE=0

usage() {
  cat <<'EOF'
usage: sudo ./deploy/bootstrap/first_boot.sh --deploy-user <linux-user> [options]

options:
  --deploy-user <linux-user>     user that should be added to the docker group
  --skip-flutter-prereqs         do not install Flutter-related Ubuntu packages
  --force-docker-replace         remove conflicting Docker packages if found
  --help                         show this help text
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --deploy-user)
      DEPLOY_USER="${2:-}"
      shift 2
      ;;
    --skip-flutter-prereqs)
      INSTALL_FLUTTER_PREREQS=0
      shift
      ;;
    --force-docker-replace)
      FORCE_DOCKER_REPLACE=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$DEPLOY_USER" ]]; then
  echo "--deploy-user is required."
  usage
  exit 1
fi

if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  echo "user '$DEPLOY_USER' does not exist."
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "cannot read /etc/os-release."
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "this bootstrap script supports Ubuntu only."
  exit 1
fi

echo "Bootstrapping Ubuntu host for Maybeflat production."
echo "Ubuntu version: ${VERSION_ID:-unknown}"
echo "Deploy user:    ${DEPLOY_USER}"

CONFLICTING_DOCKER_PACKAGES=()
while IFS= read -r package; do
  [[ -n "$package" ]] || continue
  CONFLICTING_DOCKER_PACKAGES+=("$package")
done < <(
  dpkg-query -W -f='${binary:Package}\n' \
    docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc \
    2>/dev/null || true
)

if [[ "${#CONFLICTING_DOCKER_PACKAGES[@]}" -gt 0 && "$FORCE_DOCKER_REPLACE" -ne 1 ]]; then
  echo "conflicting Docker-related packages are already installed:"
  printf '  %s\n' "${CONFLICTING_DOCKER_PACKAGES[@]}"
  echo "re-run with --force-docker-replace if you want this script to remove them."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y
apt-get install -y ca-certificates curl git gnupg ufw unzip xz-utils zip jq openssh-client

if [[ "$INSTALL_FLUTTER_PREREQS" -eq 1 ]]; then
  apt-get install -y libglu1-mesa
fi

if [[ "${#CONFLICTING_DOCKER_PACKAGES[@]}" -gt 0 ]]; then
  echo "removing conflicting Docker-related packages..."
  apt-get remove -y "${CONFLICTING_DOCKER_PACKAGES[@]}"
fi

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

usermod -aG docker "$DEPLOY_USER"

mkdir -p /var/log/caddy

cat <<EOF

Bootstrap complete.

Installed:
  - Docker Engine
  - Docker Compose plugin
  - UFW
  - git, curl, jq, unzip, xz-utils, zip, openssh-client
$(if [[ "$INSTALL_FLUTTER_PREREQS" -eq 1 ]]; then printf '  - Flutter Linux prerequisites: libglu1-mesa\n'; fi)

The user '$DEPLOY_USER' has been added to the docker group.
That group change will apply on the next login for that user.

Recommended next steps:
  1. log out and log back in as '$DEPLOY_USER'
  2. clone the repo onto the VPS
  3. create .env.production
  4. run ./deploy_production.sh
  5. install the systemd service
  6. apply the UFW firewall rules after SSH preflight checks
EOF
