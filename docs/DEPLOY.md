# Deployment

Everything here runs on the VPS as `root`. The VPS was created from the
provider's Hostinger KVM NixOS image, which already has a NixOS installation at
`/etc/nixos`; this repository replaces that with a flake-based configuration.

> **Keep the provider's original `/etc/nixos/configuration.nix`.** It is the
> only description of the disk layout the running machine was built with, and
> `modules/host.nix` mirrors it. It also doubles as a one-command fallback.

---

## 0. Prerequisites

* A domain name whose **A records point at this VPS's public IP address.**
  Caddy uses them for the Let's Encrypt HTTP-01 challenge, which needs inbound
  TCP port 80 to work. See §1.
* The `git` binary on the VPS. If it is missing:
  `nix-shell -p git --run 'git --version'`
* Root access. The provider's provisioning completes the handover of the
  machine.
* A serial console, in case the first switch goes wrong.

---

## 1. DNS

In the zone for your domain, add an A record for **each** public hostname this
machine serves. For the app server:

| Name | Type | TTL | RDATA |
|---|---|---|---|
| `app` | A | **300** | this VPS's public IPv4 |
| `portainer.app` | A | **300** | this VPS's public IPv4 |

Leave the apex records alone — `@` (203.0.113.10), `www`, `mail`, `_dmarc` and
the MX record all point at the other instance.

**Use TTL 300 for new records.** A zone's default TTL of 14400 makes resolvers
cache the NXDOMAIN for the full TTL. Caddy's ACME HTTP-01 challenge cannot
complete until that negative cache expires, and Let's Encrypt allows only 5
failed authorizations per hostname per hour, so a long TTL can leave you locked
out of a working configuration.

Verify from outside your own network:

```bash
dig +short app.example.com
dig +short portainer.app.example.com
```

Both must return this VPS's public IP **before** you deploy.

---

## 2. Get the configuration onto the VPS

From your workstation:

```bash
rsync -av --exclude .git <path-to-this-repo>/ root@<vps-ip>:/root/nix-vps/
```

or, if you have pushed the repository somewhere:

```bash
ssh root@<vps-ip>
git clone <repo-url> /root/nix-vps
```

Keep the repository out of `/etc/nixos` so that the provider's original
`configuration.nix` stays in place as a fallback.

Then create the secret files (see §4):

```bash
/root/nix-vps/scripts/init-secrets.sh
```

---

## 3. Set your values

The deployment's values live in `.env` in the repository root. Copy the
template and fill it in:

```bash
cd /root/nix-vps
cp .env.example .env
$EDITOR .env
```

```bash
PUBLIC_DOMAIN=example.com
ACME_EMAIL=admin@example.com
PUBLIC_IP=203.0.113.10
FLAKE_OUTPUT=nixos
SECRETS_DIR=secrets
```

* `PUBLIC_DOMAIN` — the base domain this machine serves. The public hostnames
  are derived from it, so `portainer.app.$PUBLIC_DOMAIN` and so on.
* `ACME_EMAIL` — the contact address registered with the ACME certificate
  authority. Used for expiry notices and abuse reports.
* `PUBLIC_IP` — the public IPv4 address of this machine. Every hostname it
  serves needs a DNS A record pointing here (§1).
* `FLAKE_OUTPUT` — the flake output to build: the file name of the machine in
  `hosts/`, without the `.nix` extension.
* `SECRETS_DIR` — where the secret files live, relative to the repository
  root. Defaults to `secrets`.

`.env` is gitignored and never committed. It is read by `scripts/rebuild.sh`,
which exports the values and evaluates the flake with `--impure` — a flake
evaluation is pure, so it cannot see the environment by itself.

`hosts/nixos.nix` holds the machine's own settings. Its `vhosts` list is the
set of public hostnames this machine serves; each entry gets its own Caddy
site block and its own certificate:

```nix
{
  hostname = "nixos";

  vhosts = [
    { name = "portainer.app.${env.domain}"; upstream = "portainer"; }
    # { name = "app.${env.domain}"; upstream = "127.0.0.1:3000"; }
  ];
}
```

* `name` — the public hostname. It needs the DNS A record from §1.
* `upstream` — `"portainer"` for the Portainer UI, or `"<host>:<port>"` for a
  container that publishes that port on loopback.

While the domain is still the placeholder `example.com`, `nixos-rebuild` prints
a warning. That warning is the reminder that you have not finished.

---

## 4. Secrets

The configuration keeps every machine's secrets in one directory, `secrets/`
in the repository root (mode 0700, files 0600). Nothing is committed to git,
and nothing lands in the Nix store — Nix only ever holds the *path* to a
file, so no secret is readable by everyone on the box.

Create the directory and the files:

```bash
/root/nix-vps/scripts/init-secrets.sh
```

```
secrets/
  portainer.env     Portainer container environment   (docker run --env-file)
  caddy.env         Caddy environment                 (optional)
```

The directory is gitignored. If you change `SECRETS_DIR` in `.env`, add the
new directory to `.gitignore` too — a *tracked* secret file would be copied
into the Nix store, which is world-readable. `scripts/rebuild.sh` checks for
that and refuses to run if it finds one.

### The Portainer setup token

A fresh Portainer refuses to be claimed by anyone who finds the port, so it
needs a one-time setup token. `scripts/init-secrets.sh` generates one for
you and writes it to `secrets/portainer.env`. You do not have to scrape it
out of the logs:

```bash
grep PORTAINER_SETUP_TOKEN /root/nix-vps/secrets/portainer.env
```

Portainer reads `PORTAINER_SETUP_TOKEN` from its environment, and the token
stays valid until you complete the first-run setup — so there is no time
pressure and no need for `docker logs`. You can delete the line afterwards.

The administrator account is created by you in the browser during that
first-run setup (§7). The configuration never holds its credentials.

---

## 5. Build and switch

```bash
cd /root/nix-vps
./scripts/rebuild.sh
```

`scripts/rebuild.sh` reads `.env`, exports the values, and runs
`nixos-rebuild switch --flake .#<machine> --impure`. The first build downloads
the NixOS closure and takes a while.

**Keep a serial console open** for the first switch. The template is
configured for `console=ttyS0,115200`, so you can watch the boot from the
provider's console view.

Useful variants:

```bash
# Build without activating:
./scripts/rebuild.sh build

# See what would change, without doing it:
./scripts/rebuild.sh switch --dry-activate

# Rebuild the initrd and boot into the new generation:
./scripts/rebuild.sh boot
```

Use `boot` rather than `switch` when the kernel or the initrd changed —
`security.lockKernelModules` only takes effect after a reboot.

**Fallback:** `nixos-rebuild switch` with no `--flake` reverts to the
provider's original `/etc/nixos/configuration.nix`.

---

## 6. Verify

```bash
# Firewall: only 22, 80 and 443 should be open.
#   80 is needed for the ACME HTTP-01 challenge and Caddy's HTTP->HTTPS redirect.
sudo iptables -S nixos-fw | grep -E 'dport|icmp'

# The machine has an address and the network is up.
#   cloud-init owns IP assignment here (see modules/host.nix), so there are no
#   NixOS-side networkd units; if this prints nothing, the boot stalled on
#   systemd-networkd-wait-online.
ip -br addr
cloud-init status --long

# Services
systemctl status docker.service caddy.service docker-portainer.service fail2ban.service

# Portainer is on loopback only:
ss -ltnp | grep 9443
#   LISTEN 0 4096 127.0.0.1:9443 0.0.0.0:*

# Caddy is public on 443:
ss -ltnp | grep 443

# The certificate was issued:
journalctl -u caddy.service | grep -i certificate
curl -I https://portainer.app.example.com
```

The Portainer container is managed by systemd under the name
`docker-portainer`:

```bash
systemctl status docker-portainer.service
journalctl -u docker-portainer.service -f
```

---

## 7. First-run setup for Portainer

Portainer 2.43 and newer require a one-time setup token, so that a freshly
started instance cannot be claimed by somebody else.

If you set `PORTAINER_SETUP_TOKEN` in `secrets/portainer.env` (§4), use
that one:

```bash
grep PORTAINER_SETUP_TOKEN /root/nix-vps/secrets/portainer.env
```

Open `https://portainer.app.example.com` in a browser, paste the token,
and create the administrator account. Your token has no expiry, so there is
no time pressure.

If you did not set one, Portainer generates its own and prints it in the
logs. That one **is** only valid for five minutes:

```bash
docker logs portainer 2>&1 | grep setup_token
```

If you missed that window, restart the service and read a fresh token:

```bash
systemctl restart docker-portainer.service
```

The Portainer database lives in the `portainer_data` Docker volume, so the
administrator account survives restarts and rebuilds.

---

## 8. Post-provisioning lockdown

The provider's provisioning logs in as `root` during handover, so root login is
still enabled at that point. Once handover is finished and you are signed in
with an SSH key, lock it down.

1. **Add your SSH key** (already done by cloud-init if you supplied one at
   order time). Verify it works:

   ```bash
   ssh -o PreferredAuthentications=publickey root@<vps-ip> 'echo ok'
   ```

2. **Restrict SSH to key authentication.** Edit `modules/host.nix` and, inside
   `services.openssh.settings`, set `PermitRootLogin` to the value that lets
   root sign in with a key only, and turn off the remaining interactive
   authentication methods. The exact directive names and their accepted values
   are listed in the `services.openssh.settings` option index.

   And remove the `PermitRootLogin = lib.mkDefault "yes";` line from
   `modules/host.nix`, otherwise the `mkDefault` there wins over your
   setting.

3. **Rebuild and confirm** that you can still get in with your key:

   ```bash
   ./scripts/rebuild.sh
   # do NOT close your current session yet
   ssh -o PreferredAuthentications=publickey root@<vps-ip> 'echo ok'
   ```

4. Add your own fixed IP to `services.fail2ban.ignoreIP` in
   `modules/security.nix` if you have one, so a misconfiguration can never lock
   you out.

---

## 9. Putting an application on its own hostname

1. **In Portainer**, create the container and publish its port on **loopback
   only**, for example `127.0.0.1:3000:3000`. Publishing on `0.0.0.0` exposes
   the port to the internet and bypasses the NixOS firewall, because Docker
   installs its own DNAT rules ahead of it.

2. **Add a DNS A record** for the hostname, TTL 300, pointing at this VPS.

3. **Add a vhost entry** to `hosts/nixos.nix`:

   ```nix
   {
     name = "myapp.app.${env.domain}";
     upstream = "127.0.0.1:3000";
   }
   ```

4. **Rebuild:**

   ```bash
   ./scripts/rebuild.sh
   ```

Caddy then requests a certificate for the new name and starts proxying it.

> Each hostname needs its own A record **and** its own certificate. There are
> no wildcard certificates here, because the DNS provider has no API for a
> DNS-01 challenge. Let's Encrypt allows 50 new certificates per registered
> domain per week, so a handful of applications is fine.

---

## 10. Managing a second machine

To manage another VPS with this repository, add a `hosts/<name>.nix` file. The
file name becomes the flake output name:

```nix
# hosts/other.nix
let
  env = import ../lib/env.nix;
in
{
  hostname = "other";

  domain = env.domain;

  acmeEmail = env.acmeEmail;

  publicIp = env.publicIp;

  vhosts = [
    { name = "other.${env.domain}"; upstream = "portainer"; }
  ];
  secrets = {
    dir = env.secretsDir;
  };
}
```

`acmeEmail` is required — the modules read it from `hostConfig` and the
evaluation fails without it. `domain`, `publicIp` and `secrets` are optional
and fall back to a placeholder. `env` is the same `../lib/env.nix` that reads
the deployment values from the environment. The `secrets` path is relative to
the checkout, so a machine needs no absolute path anywhere.

```bash
FLAKE_OUTPUT=other ./scripts/rebuild.sh
```

Machines running a different provider image also need an
`hosts/<name>.extra.nix` file with the disk, boot loader and provisioning
overrides that differ from `modules/host.nix`.

## 11. Routine operations

### Updates

```bash
cd /root/nix-vps
git pull                                   # if you cloned a remote
nix flake update                           # move nixpkgs forward
git diff                                   # review what changed
./scripts/rebuild.sh
./scripts/rebuild.sh boot                  # if the kernel/initrd changed
```

`nix flake update` is the only supported way to move this machine forward.
`nixos-rebuild --upgrade` resolves against a channel and would take the
configuration off the pin.

### Upgrading Portainer

Portainer is pinned by digest in `modules/portainer.nix`. To move it:

```bash
# Find the new digest
docker buildx imagetools inspect portainer/portainer-ce:<version> | grep Digest
```

Put the digest in `modules/portainer.nix`, rebuild, and pull the new image:

```bash
docker pull portainer/portainer-ce@sha256:<new-digest>
./scripts/rebuild.sh
```

### Rollback

Every activation leaves a bootable generation behind:

```bash
nixos-rebuild list-generations          # available on nixos-rebuild-ng
nixos-rebuild switch --flake .#nixos --rollback   # or:
nixos-rebuild boot --generation <n>
```

`/nix/var/nix/profiles/system-<n>-link` is the previous system closure.

### Disk

Docker images and build cache are the usual space consumers:

```bash
docker system df
docker system prune -a          # manual, aggressive: removes unused images
```

The configuration also runs `docker system prune -f` weekly
(`virtualisation.docker.autoPrune`). It does **not** prune volumes, so
`portainer_data` and your application volumes are safe.

### Logs

```bash
journalctl -u docker-portainer.service -f   # Portainer
journalctl -u caddy.service -f              # reverse proxy
journalctl -k | grep DROP                   # firewall drops
docker logs portainer                       # Portainer's own output
```

---

## 12. What to read next

* [`SECURITY.md`](SECURITY.md) — every hardening decision and its source.
* [`research/nixos-vps-security-hardening.md`](research/nixos-vps-security-hardening.md)
  — the underlying research.
