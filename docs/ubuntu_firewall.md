# Ubuntu Firewall Lockdown

This setup uses `ufw` on the VPS to:

- allow `22/tcp` only from your admin IP addresses
- allow `80/tcp` and `443/tcp` only from Cloudflare's published proxy IP ranges
- deny all other inbound traffic

This is the right shape when `maybeflat.com` is orange-clouded in Cloudflare and your VPS should only accept web traffic that has already passed through Cloudflare.

## Important Warning

Do not run the firewall script until you know the exact public IP or CIDR block you will SSH from.

If you pass the wrong SSH CIDR, you can lock yourself out of the VPS.

## Script

Use the included script:

```bash
chmod +x deploy/firewall/apply_ufw_firewall.sh
sudo ./deploy/firewall/apply_ufw_firewall.sh 198.51.100.24/32
```

You can pass more than one SSH source:

```bash
sudo ./deploy/firewall/apply_ufw_firewall.sh 198.51.100.24/32 203.0.113.18/32
```

If your SSH daemon listens on a custom port:

```bash
sudo SSH_PORT=2222 ./deploy/firewall/apply_ufw_firewall.sh 198.51.100.24/32
```

The script fetches the current Cloudflare IPv4 and IPv6 ranges directly from:

- `https://www.cloudflare.com/ips-v4`
- `https://www.cloudflare.com/ips-v6`

## Safer Preflight

Run the preflight helper from the machine you normally use to SSH into the VPS.

It will:

- detect your current public IP
- suggest the CIDR to allow for SSH
- test SSH access to the server
- check whether `ufw` and `curl` exist on the VPS

Example:

```bash
chmod +x deploy/firewall/preflight_ssh_access.sh
./deploy/firewall/preflight_ssh_access.sh your-linux-user maybeflat.com 22
```

If the script reports a public IPv4 address like `198.51.100.24`, use `198.51.100.24/32`.

If it reports an IPv6 address, use `/128` instead.

## Timed Rollback Guard

Before applying the firewall on the VPS, you can arm an automatic rollback.

Example:

```bash
chmod +x deploy/firewall/ufw_rollback_guard.sh
sudo ./deploy/firewall/ufw_rollback_guard.sh arm 10
```

That schedules `ufw --force disable` in 10 minutes unless you disarm it.

After you confirm that:

- SSH still works
- `https://maybeflat.com` still loads
- `https://maybeflat.com/api/health` still responds

disarm the rollback:

```bash
sudo ./deploy/firewall/ufw_rollback_guard.sh disarm
```

## What The Script Does

1. sets `ufw default deny incoming`
2. sets `ufw default allow outgoing`
3. allows SSH from the CIDR blocks you pass in
4. allows `80/tcp` and `443/tcp` from the current Cloudflare IP ranges
5. enables `ufw`

## Before You Run It

1. Confirm Cloudflare proxying is enabled for `maybeflat.com`.
2. Confirm you can already SSH into the VPS from the IP you plan to allow.
3. Confirm `ufw` and `curl` are installed.
4. If you use IPv6 for SSH, include your IPv6 admin CIDR too.
5. If you use a custom SSH port, pass `SSH_PORT=...`.
6. For extra safety, arm the rollback guard before changing UFW rules.

## After You Run It

Check:

```bash
sudo ufw status verbose
curl -I https://maybeflat.com
curl -I https://maybeflat.com/api/health
```

From a machine that is not your allowed SSH source, direct SSH access should fail.

## Updating Cloudflare Ranges Later

Cloudflare can change its published IP ranges over time. Re-run the script when you want to refresh the allowlist.

Because the script fetches the ranges live from Cloudflare, it uses the current published lists at execution time.
