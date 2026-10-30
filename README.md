# nix-vps

A security-hardened **NixOS 26.05** configuration for Hostinger KVM VPSs, with
**Docker** and **Portainer CE** for running and managing application
containers, and **Caddy** in front of Portainer for real TLS.

Everything is declarative, pinned in a flake, and reproducible from this
repository.

---

## What runs where

```
                       internet
                          │
                    :22   │   :443
              ┌───────────┴───────────┐
              │   NixOS firewall       │   only 22/tcp and 443/tcp(+udp)
              │   (networking.firewall)│   are accepted
              └───────────┬───────────┘
                          │
              ┌───────────┴───────────┐
              │  Caddy  (systemd)     │  Let's Encrypt certificate,
              │  services.caddy       │  automatic renewal
              └───────────┬───────────┘
                          │  127.0.0.1:9443  (loopback only)
              ┌───────────┴───────────┐
              │  Portainer CE         │  systemd unit:
              │  docker-portainer     │  docker-portainer.service
              └───────────┬───────────┘
                          │  /var/run/docker.sock
              ┌───────────┴───────────┐
              │  Docker Engine        │  overlay2, journald logs,
              │  docker.service       │  live-restore, no-new-privileges
              └───────────┬───────────┘
                          │
                  your application containers
```

The important part of that diagram: **Portainer is published on `127.0.0.1`
only.** Docker installs its own DNAT rules ahead of the NixOS firewall, so a
container port published on `0.0.0.0` is reachable no matter what
`networking.firewall` says. Binding to loopback is what keeps the firewall
meaningful.

---

## Machines

This repository manages more than one machine. Every file in `hosts/` is a
machine; the file name is the flake output name.

| File | Machine | Serves |
|---|---|---|
| `hosts/nixos.nix` | this VPS | `portainer.app.$PUBLIC_DOMAIN` |

Every machine runs the same Hostinger KVM image, so they share
`modules/host.nix` unchanged. To manage another machine, add a
`hosts/<name>.nix` file: the file name becomes the flake output name, and an
optional `hosts/<name>.extra.nix` next to it is imported as an extra NixOS
module for per-machine overrides.

```bash
./scripts/rebuild.sh              # this VPS
FLAKE_OUTPUT=other ./scripts/rebuild.sh   # a machine added later
```

---

## DNS

Each public hostname a machine serves needs a DNS A record pointing at that
machine's public IP, and nothing else. For the app server:

| Name | Type | TTL | RDATA |
|---|---|---|---|
| `app` | A | 300 | app server's public IPv4 |
| `portainer.app` | A | 300 | app server's public IPv4 |

Use a **low TTL (300)** for new records. A zone's long TTL makes resolvers
cache the NXDOMAIN for hours, and Caddy's ACME HTTP-01 challenge cannot
complete until it expires.

The apex records (`@`, `www`, `mail`, `_dmarc`, MX) point at the other
instance and are left alone.

> **No wildcard certificates.** The DNS provider here has no public API, so
> only DNS-01 is impossible — which means only HTTP-01 is available, and a
> wildcard `*.app.$PUBLIC_DOMAIN` would need a DNS-01 challenge with an
> API token. Every hostname in the app zone therefore gets its own A record
> and its own certificate.

---

## Repository layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Flake entry point. Pins nixpkgs to the `nixos-26.05` branch, discovers the machines in `hosts/`. |
| `flake.lock` | The exact nixpkgs revision. Do not edit by hand. |
| `.env.example` | Template for the deployment values. Copy it to `.env`. |
| `lib/env.nix` | Reads the deployment values from the environment. |
| `hosts/nixos.nix` | This machine: hostname, public hostnames, secret paths. **Edit this.** |
| `modules/secrets.nix` | Wires the per-machine secret files to the services that need them. |
| `scripts/init-secrets.sh` | Creates the secret directory and files on a machine. |
| `scripts/rebuild.sh` | Rebuilds the machine with the values from `.env`. |
| `configuration.nix` | Module wiring and the placeholder warnings. |
| `modules/host.nix` | Disk layout, boot loader, cloud-init, guest agent. Mirrors the provider image. |
| `modules/security.nix` | Firewall, kernel hardening, fail2ban, Nix store hygiene, log retention. |
| `modules/docker.nix` | Docker daemon and its hardening options. |
| `modules/portainer.nix` | Portainer CE as a systemd-managed container. |
| `modules/proxy.nix` | Caddy: TLS termination and reverse proxy for each public hostname. |
| `docs/DEPLOY.md` | Step-by-step deployment, first-run setup, updates, rollback. |
| `docs/SECURITY.md` | Every hardening decision, its rationale and its primary source. |
| `docs/research/` | The research that preceded the configuration, with citations. |

---

## Configuration values

The deployment's own values — the domain, the ACME contact address, the
public IP — live in `.env` in the repository root, not in this file and not
in the tracked tree. Copy the template and fill it in:

```bash
cp .env.example .env
$EDITOR .env
```

| Variable | Meaning |
|---|---|
| `PUBLIC_DOMAIN` | The base domain this machine serves. The public hostnames are derived from it. |
| `ACME_EMAIL` | The contact address registered with the ACME certificate authority. |
| `PUBLIC_IP` | The public IPv4 address of this machine. Every hostname it serves needs a DNS A record pointing here. |
| `FLAKE_OUTPUT` | The flake output to build: the file name of the machine in `hosts/`, without the `.nix` extension. |

`.env` is gitignored. Nix cannot read it directly — a flake evaluation is
pure, so it cannot see the environment — so `scripts/rebuild.sh` sources the
file, exports the values, and evaluates the flake with `--impure`. Without
those values every lookup falls back to its placeholder (`example.com`), so a
plain checkout always evaluates to something harmless.

---

## Deploying

```bash
# On the VPS, as root:
cp -a /etc/nixos /root/nixos-template-backup   # keep the provider's template

rsync -av --exclude .git <path-to-this-repo>/ root@<vps-ip>:/root/nix-vps/
cd /root/nix-vps

# 1. Set your domain, contact address and public IP.
cp .env.example .env
$EDITOR .env

# 2. Create the secret files (mode 0600, not in git).
./scripts/init-secrets.sh
openssl rand -hex 16 | sed 's/^/PORTAINER_SETUP_TOKEN=/' >> /etc/nix-vps/portainer.env

# 3. Confirm DNS already points here.
dig +short portainer.app.example.com

# 4. Build and switch. Keep a console session open.
./scripts/rebuild.sh
```

`/etc/nixos/configuration.nix` is left untouched as the provider's original
template, so `nixos-rebuild switch` (with no `--flake`) is a one-command
fallback.

Full instructions, including the Portainer first-run flow, are in
[`docs/DEPLOY.md`](docs/DEPLOY.md).

---

## Security posture in one screen

| Layer | What is done |
| --- | --- |
| Network | NixOS firewall enabled; only 22/tcp and 443/tcp+udp accepted. nftables deliberately off (Docker needs iptables). Reverse-path filtering strict. |
| SSH | Key-based, `MaxAuthTries 3`, no X11 forwarding, idle sessions disconnected, fail2ban with escalating ban times. |
| Kernel | NixOS Wiki hardening baseline (kptr_restrict, rp_filter, no redirects, no BPF JIT, no ftrace, io_uring disabled for unprivileged). Module loading locked after boot. |
| Docker | `overlay2`, `live-restore`, `icc=false`, `no-new-privileges=true`, `journald` log driver, weekly prune, journal capped at 512 MB. The `docker` group is left **empty** because it is root-equivalent. |
| Portainer | Digest-pinned image, published on loopback only, `docker.sock` mounted (unavoidable — it is how Portainer works), first-run setup token required. |
| TLS | Real Let's Encrypt certificate via Caddy, HSTS, HTTP/3. |
| Store & logs | Build sandbox on, store auto-optimised, GC after 30 days, journal size-capped. |

The reasoning and the primary source for every line of that table is in
[`docs/SECURITY.md`](docs/SECURITY.md).

---

## Managing applications

Point a browser at `https://portainer.app.$PUBLIC_DOMAIN` and paste the
`PORTAINER_SETUP_TOKEN` from `/etc/nix-vps/portainer.env`. From there:
**Containers → Add container**, or **Stacks → Add stack** for compose files.

Application secrets are Portainer's job, not Nix's: set them on the container
in Portainer, and they never pass through this repository.

To put an application on its own hostname:

1. Publish the container's port on **loopback only** in Portainer, for
   example `127.0.0.1:3000:3000`.
2. Add a DNS A record for its hostname.
3. Add a vhost entry to `hosts/nixos.nix`:

   ```nix
   {
     name = "myapp.app.${env.domain}";
     upstream = "127.0.0.1:3000";
   }
   ```

4. Rebuild: `./scripts/rebuild.sh`.

Two things to know:

* **Container ports are not firewalled by NixOS.** When you publish a port in
  Portainer, bind it to `127.0.0.1` and put a reverse proxy in front of it,
  the same way Portainer itself is deployed here. Publishing on `0.0.0.0`
  exposes the port to the whole internet.
* **`no-new-privileges` is on by default** for every container. If an image
  genuinely needs it, add the security option `no-new-privileges:false` to
  that container.

## Secrets

Per-machine secret files live in `/etc/nix-vps/` (mode 0700, root only), never
in git and never in the Nix store — Nix only ever holds the *path*:

| File | Fed to | Contains |
|---|---|---|
| `portainer.env` | Portainer container, `docker run --env-file` | `PORTAINER_SETUP_TOKEN=…` |
| `caddy.env` | Caddy, `EnvironmentFile=-…` | optional (ACME EAB etc.) |

`scripts/init-secrets.sh` creates the directory and the files. Because the
setup token comes from an env file rather than the command line, it never
appears in `ps`, in the systemd unit, or in the world-readable Nix store. The
Portainer administrator account is created by you in the browser during the
first-run setup; the configuration never holds its credentials.

---

## Updating

This configuration is pinned to a flake, so `nixos-rebuild --upgrade` (which
resolves against a *channel*) would silently drift the machine off the pinned
configuration. The supported procedure is:

```bash
cd /root/nix-vps
nix flake update          # move nixpkgs to the current nixos-26.05 revision
git diff                  # review what changed
./scripts/rebuild.sh
```

See [`docs/DEPLOY.md`](docs/DEPLOY.md#updates).

---

## Notes

* The disk layout, boot loader and cloud-init wiring in `modules/host.nix`
  must keep matching the provider image. Changing them can make the machine
  unbootable.
* `system.stateVersion = "26.05"` is a data-format version, not a package
  version. Do not bump it casually.
* `system.autoUpgrade` is intentionally off. See
  [`docs/SECURITY.md`](docs/SECURITY.md#automatic-upgrades).
