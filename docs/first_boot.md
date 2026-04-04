# First Boot On Ubuntu VPS

This script prepares a fresh Ubuntu VPS for the Maybeflat self-hosted production path.

It installs:

- Docker Engine from Docker's official Ubuntu apt repository
- Docker Compose plugin
- `ufw`
- `git`, `curl`, `jq`, `unzip`, `xz-utils`, `zip`, `openssh-client`
- `libglu1-mesa` by default for the Flutter CLI runtime

Script path:

- `deploy/bootstrap/first_boot.sh`

## What It Does

1. checks that the host is Ubuntu
2. updates and upgrades apt packages
3. installs the base packages this deployment path expects
4. installs Docker Engine from Docker's official apt repository
5. adds your deploy user to the `docker` group
6. creates `var/log/caddy` prerequisites on the host

## Safe Behavior

If the VPS already has conflicting Docker packages installed, the script exits instead of removing them automatically.

If you really want the script to replace those packages, run it again with:

```bash
sudo ./deploy/bootstrap/first_boot.sh --deploy-user your-linux-user --force-docker-replace
```

This is intentionally conservative so the bootstrap does not silently modify an existing Docker setup.

## Run It

```bash
chmod +x deploy/bootstrap/first_boot.sh
sudo ./deploy/bootstrap/first_boot.sh --deploy-user your-linux-user
```

If you do not want the Flutter-related Ubuntu package:

```bash
sudo ./deploy/bootstrap/first_boot.sh --deploy-user your-linux-user --skip-flutter-prereqs
```

## Important Note About Flutter

The script installs the Linux package prerequisites that help the Flutter CLI run cleanly, but it does not install the Flutter SDK itself.

That is deliberate.

The exact Flutter SDK version you want on the VPS is a release-management choice. For this repo, you have two reasonable paths:

- install Flutter manually on the VPS, then use `./deploy_production.sh`
- avoid installing Flutter on the VPS and instead ship prebuilt `app_flutter/build/web` assets from CI or another machine

Because the current production deploy script builds the web app on the VPS, you will need a working `flutter` command there unless you change that workflow.

## Recommended Next Steps

1. Install the Flutter SDK on the VPS if you plan to keep building there.
2. Clone the repo.
3. Copy `.env.production.example` to `.env.production`.
4. Run `./deploy_production.sh`.
5. Install the systemd unit.
6. Run the SSH preflight helper.
7. Apply the UFW firewall rules.
