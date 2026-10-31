# Security decisions

Every hardening decision in this configuration, the reasoning behind it, and
the primary source it is based on. The research that preceded the
configuration — including the options that were checked and *rejected* — is in
[`research/nixos-vps-security-hardening.md`](research/nixos-vps-security-hardening.md).

**Target:** NixOS 26.05 (current stable), `nixpkgs` revision
`6f06d204d8f2d8761d9da78778745974a3216381`, pinned in `flake.lock`.

**Host:** Hostinger KVM VPS on Proxmox. Single virtio NIC, static IP assigned
by cloud-init, BIOS/SeaBIOS GRUB on a single legacy MBR disk, ext4 root.

---

## 1. Threat model

The host runs third-party application containers that are updated by someone
else and are reachable from the internet. So the realistic adversaries are:

1. **Opportunistic internet background noise** — port scanners, SSH
   brute-forcers, mass exploitation of a CVE in a published container image.
2. **A compromised application container** — a malicious or exploited image
   trying to break out, read the host filesystem, or pivot.
3. **A stolen Portainer session** — Portainer is a full host-management
   interface, so compromising it is equivalent to compromising the host.

Design responses, in order:

* Keep the number of internet-reachable ports at two (22 and 443).
* Make the container runtime the place where untrusted code runs, and strip
  the daemon's own defaults in the direction of "less privilege".
* Make the management interface unreachable except through a TLS proxy, and
  put a real certificate in front of it.

---

## 2. Network perimeter

### 2.1 The firewall is `networking.firewall`, not `security.firewall`

There is no `security.firewall` option in nixpkgs. The module is
`networking.firewall`, and it is enabled by default. `logChanges` and
`forwardPorts` do not exist either; the real names are
`logRefusedConnections` / `logRefusedPackets` and `filterForward`.

*Source:* `nixos/modules/services/networking/firewall.nix` on `nixos-26.05`;
the NixOS Manual, "Firewall" section.

### 2.2 Only 22 and 443 are accepted

```nix
networking.firewall.allowedTCPPorts = [ 22 ];
```

`services.openssh` opens 22 automatically. Caddy opens 80 and 443 for itself
through `services.caddy.openFirewall`, whose default is `false` — so it is set
explicitly to `true` in `modules/proxy.nix`. Port 80 is needed for the ACME
HTTP-01 challenge; it also serves Caddy's automatic HTTP→HTTPS redirect.

`services.caddy.openFirewall` also opens UDP 443, because Caddy enables
HTTP/3 by default.

### 2.3 `networking.nftables.enable = false` — deliberately

The option's own text says:

> *"Note that if you have Docker enabled you will not be able to use nftables
> without intervention. Docker uses iptables internally to setup NAT for
> containers."*

The firewall therefore stays on the **iptables** backend, which is also what
`fail2ban` uses by default (`services.fail2ban.packageFirewall` follows
`networking.firewall.package`).

*Source:* `networking.nftables.enable` option text, `nixos-26.05`.

### 2.4 Strict reverse-path filtering

```nix
networking.firewall.checkReversePath = "strict";
boot.kernel.sysctl."net.ipv4.conf.all.rp_filter" = 1;
```

This VPS has a single network interface, so the default route always points
back at the interface a packet arrived on, and strict mode is safe and
stronger than loose mode.

**Escape hatch:** if the provider ever gives you a second interface with
asymmetric routing, set `checkReversePath = "loose"` and the two `rp_filter`
sysctls to `2` together, or legitimate traffic will be dropped. This is
recorded here because it is the single most likely thing to need changing on
this machine.

### 2.5 Drop, not reject

`networking.firewall.rejectPackets = false` is the default and is kept
explicitly. The option text says: *"Rejecting packets makes port scanning
somewhat easier."*

### 2.6 Docker-published ports bypass the firewall — the central constraint

From `virtualisation.oci-containers.containers.<name>.ports`:

> *"Publishing a port bypasses the NixOS firewall. If the port is not supposed
> to be shared on the network, make sure to publish the port to localhost.
> Example: `127.0.0.1:1234:1234`"*

Docker installs its own DNAT rules ahead of the NixOS input chain, so the
same is true of `docker run -p`. This is why **Portainer is published on
`127.0.0.1:9443` only** and fronted by Caddy. The firewall is then genuinely
in the path.

The same applies to every application container you deploy later: publish on
`127.0.0.1` and put a reverse proxy in front of it.

---

## 3. SSH

| Setting | Value | Why |
| --- | --- | --- |
| `PermitRootLogin` | `mkDefault "yes"` | The provider's provisioning logs in as root during handover. Locking this down before handover finishes would lock you out. See the lockdown procedure in `DEPLOY.md`. |
| `X11Forwarding` | `false` | Unneeded on a server; a redirect target for an attacker. |
| `MaxAuthTries` | `3` | Bounds authentication attempts per connection. |
| `LoginGraceTime` | `30` | Bounds how long a half-open connection occupies a slot. |
| `ClientAliveInterval` / `ClientAliveCountMax` | `300` / `2` | Disconnects idle sessions. |
| `LogLevel` | `VERBOSE` (set by nixpkgs) | fail2ban cannot see failed logins without it. |

### fail2ban

`services.fail2ban.enable = true`, `maxretry = 3`, `bantime = "1h"`, with
`bantime-increment` enabled (factor `2`, cap `1d`) so repeat offenders get
progressively longer bans.

NixOS ships a default `sshd` jail: the fail2ban module defines
`services.fail2ban.jails.sshd.settings.port` whenever `services.openssh.enable`
is true, and the jail submodule's `enabled` option defaults to `true`, so the
jail is active without extra configuration. The module also sets
`services.openssh.settings.LogLevel` to `VERBOSE` when fail2ban is enabled,
which is what the jail needs.

> `services.fail2ban.ignoreIP` is intentionally empty in the repository.
> **Add your own fixed IP or VPN range** before you rely on the jail, so that a
> misconfiguration cannot lock you out.

*Source:* `nixos/modules/services/security/fail2ban.nix` on `nixos-26.05`.

---

## 4. Kernel

### 4.1 Sysctl baseline

The values in `modules/security.nix` are the baseline published on the
**NixOS Wiki hardening page**, which is first-party NixOS documentation:

```nix
boot.kernel.sysctl."kernel.kptr_restrict"              = 2;
boot.kernel.sysctl."net.core.bpf_jit_enable"            = false;
boot.kernel.sysctl."kernel.ftrace_enabled"               = false;
boot.kernel.sysctl."kernel.io_uring_disabled"            = 2;
boot.kernel.sysctl."net.ipv4.conf.all.log_martians"      = true;
boot.kernel.sysctl."net.ipv4.conf.all.rp_filter"         = 1;
boot.kernel.sysctl."net.ipv4.conf.default.log_martians"  = true;
boot.kernel.sysctl."net.ipv4.conf.default.rp_filter"     = 1;
boot.kernel.sysctl."net.ipv4.icmp_echo_ignore_broadcasts" = true;
boot.kernel.sysctl."net.ipv4.conf.all.accept_redirects"    = false;
boot.kernel.sysctl."net.ipv4.conf.all.secure_redirects"    = false;
boot.kernel.sysctl."net.ipv4.conf.default.accept_redirects" = false;
boot.kernel.sysctl."net.ipv4.conf.default.secure_redirects" = false;
boot.kernel.sysctl."net.ipv6.conf.all.accept_redirects"    = false;
boot.kernel.sysctl."net.ipv6.conf.default.accept_redirects" = false;
boot.kernel.sysctl."net.ipv4.conf.all.send_redirects"       = false;
```

*Source:* <https://wiki.nixos.org/wiki/NixOS_Hardening>.

Known cost: `kernel.ftrace_enabled = false` breaks `bpftrace` and some
profiling tools. `kernel.io_uring_disabled = 2` disables io_uring for
unprivileged processes only; privileged callers still have it.

### 4.2 IP forwarding cannot be disabled while Docker is on

nixpkgs' docker module sets:

```nix
boot.kernel.sysctl = {
  "net.ipv4.conf.all.forwarding"     = mkOverride 98 true;
  "net.ipv4.conf.default.forwarding" = mkOverride 98 true;
};
```

`mkOverride 98` is a high-priority override, so `net.ipv4.ip_forward = false`
is silently ignored. Any hardening advice that tells you to turn off IPv4
forwarding is not actionable on a NixOS Docker host.

*Source:* `nixos/modules/virtualisation/docker.nix` on `nixos-26.05`.

### 4.3 Kernel module lockdown

```nix
security.lockKernelModules = true;
```

Closes a common container-escape and rootkit path: after boot, nothing can
load a new kernel module.

Safe here because:

* nixpkgs' docker module adds `bridge`, `veth`, `br_netfilter` and `xt_nat`
  to `boot.kernelModules` for Docker.
* `modules/host.nix` loads the virtio modules (`virtio_blk`, `virtio_net`,
  `virtio_pci`, `virtio_scsi`, `virtio_rng`) explicitly rather than relying on
  udev, so the machine cannot come up without disk or network once the
  lockdown is in place. All of them exist in the NixOS kernel: the first four
  are listed in the `qemu-guest` profile's `boot.initrd.availableKernelModules`,
  and `virtio_rng` is in that profile's `boot.initrd.kernelModules` (it is
  loaded, not merely available, so it is not in the `available` set). The
  kernel ships the file as `virtio-rng.ko`; modprobe normalises the `-`/`_`
  difference, so `virtio_rng` still resolves.

**Cost:** any module you need later has to be added to `boot.kernelModules`
and the machine rebooted. **Note:** this takes effect on the next reboot, so
use `nixos-rebuild boot`, not `switch`.

### 4.4 MAC is not part of this strategy

The NixOS Wiki states that SELinux *"proper integration does not exist"* on
NixOS, and that as of April 2026 AppArmor *"is available for NixOS but also
has not yet been properly integrated."* The `security.apparmor.enable` option
text itself warns that enabling it *"privileges stability over security"* and
requires a reboot.

Docker's seccomp profile and capability bounding sets are the effective
mandatory-access-control layer here, so the configuration relies on those
rather than on AppArmor.

*Source:* <https://wiki.nixos.org/wiki/Security>.

---

## 5. Docker

### 5.1 Daemon settings

| Key | Value | Effect |
| --- | --- | --- |
| `live-restore` | `true` | Containers survive a dockerd restart (daemon upgrade, config change). Incompatible with Docker Swarm, which this host does not use. nixpkgs leaves this **unset** for `stateVersion >= 24.11`, so it has to be requested explicitly. |
| `icc` | `false` | Containers on the *default* bridge cannot talk to each other. User-defined networks — what Portainer stacks and compose projects create — are unaffected. |
| `no-new-privileges` | `true` | Containers cannot gain privileges through setuid or file-capability binaries. The most useful daemon-wide default for a host running third-party images. |
| `default-ulimits` | `nofile` 64000 | The Docker default of 1024 is too low for anything holding many files open. |

`storage-driver` is `overlay2` and `log-driver` is `journald`. The log driver
matters: nixpkgs defaults it to `journald` (upstream defaults to `json-file`),
so container output lands in the systemd journal and is covered by the journal
size cap, instead of growing unbounded json files on the root filesystem.

*Source for all keys:* <https://docs.docker.com/reference/cli/dockerd/> —
the "Daemon configuration file" reference, and the full example of allowed
configuration options on Linux.

### 5.2 What is deliberately NOT set

* **`hosts`** — nixpkgs pre-seeds `hosts = [ "fd://" ]` (systemd socket
  activation). Upstream warns: *"On systems that use systemd to start the
  Docker daemon, `-H` is already set, so you can't use the `hosts` key in
  `daemon.json` to add listening addresses."*
* **`ExecStart`** — nixpkgs already passes `--config-file=<store path>`. Setting
  it yourself breaks the daemon.json wiring.
* **`userns-remap`** — the strongest single mitigation for container breakout
  upstream offers, but it breaks Portainer: the daemon socket is owned by real
  uid 0, and a userns-remapped container's root is not uid 0 on the host, so
  it loses access to `docker.sock`. It also breaks applications that bind-mount
  host paths and expect specific ownership. **Decide before pulling any
  images** — remapping changes the ownership of everything in
  `/var/lib/docker`.
* **`userland-proxy = false`** — would break Caddy's access to Portainer,
  because the host cannot reach a container's published port over loopback
  without the userland proxy.
* **Rootless Docker** (`virtualisation.docker.rootless.enable`) — the cleanest
  fix for the `docker`-group-is-root problem, but Portainer's own documentation
  says rootless Docker *"has some limitations, and requires additional
  configuration"*, and NixOS support for it is rougher. Not enabled; see
  "Accepted risks".

### 5.3 The `docker` group is root-equivalent

Docker's own words:

> *"The `docker` group grants root-level privileges to the user."*
> — <https://docs.docker.com/engine/install/linux-postinstall/>

and from the daemon attack-surface page:

> *"you can start a container where the `/host` directory is the `/` directory
> on your host; and the container can alter your host filesystem without any
> restriction."*

nixpkgs creates the socket as `root:docker` with mode `0660`, so membership of
that group is equivalent to root. **The group is therefore left empty.** The
`docker` CLI is available to root through sudo, and application management
happens through Portainer. If you want CLI access as a non-root user, add it
knowingly: `users.users.<name>.extraGroups = [ "docker" ];`.

### 5.4 Automatic prune, without pruning volumes

`virtualisation.docker.autoPrune` runs `docker system prune -f` weekly. It
does not prune volumes, and `autoPrune.allVolumes.enable` stays `false`.
Anonymous volumes are left alone too, because pruning them would silently
destroy data for applications that declare their volumes anonymously.

---

## 6. Portainer

### 6.1 Docker backend, not Podman, not the raw binary

Portainer's official documentation lists four Linux install methods: Docker
standalone, Docker Swarm, Podman and Kubernetes. There is **no documented
binary/systemd install**. The upstream repository does ship a
`distribution/portainer.service`, so a native-binary install is possible, but
it is not a supported path and the NixOS layout would have to be adapted by
hand.

The Podman path requires `--privileged`, and Portainer itself says Podman
support *"is limited to configurations where that Docker-compatible API
behaves consistently"*.

The Docker path is the one Portainer documents and tests, so it is used here —
and nixpkgs' `virtualisation.oci-containers` module can drive it natively, with
`backend = "docker"`, which generates the systemd unit, orders it after
`docker.service` and `docker.socket`, and waits for `network-online.target`
before pulling the image.

*Source:* <https://docs.portainer.io/start/install-ce/server/docker/linux>.

### 6.2 The generated command

```bash
docker run \
  --name=portainer \
  --log-driver=journald \
  -p 127.0.0.1:9443:9443 \
  -v /run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  --pull missing \
  docker.io/portainer/portainer-ce@sha256:3609c307943bca8e5c492f69ddd6965df177208b50678a4cff28391c8dd4e96e
```

This matches Portainer's documented install (`docker run -d -p 9443:9443 -v
/var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data`), with three
differences:

* **Loopback only** instead of `0.0.0.0`, so the firewall stays in the path.
* **No `-d`** — the container runs in the foreground under systemd, so
  systemd tracks its real state and restarts it when it fails.
* **Pinned by digest**, so a rebuild always produces the same container.

`portainer_data` is the volume name from Portainer's official documentation.

### 6.3 The `docker.sock` mount is unavoidable — and it is the real risk

Portainer's documented install requires the Docker socket. There is no
supported alternative for a Docker-backed Portainer. The consequence must be
stated plainly: **Portainer is root-equivalent on this host**, because it can
start a container with the host filesystem mounted.

Mitigations that are in place:

* The Portainer UI is not reachable except through Caddy over TLS.
* Portainer's first run requires a one-time setup token, so a freshly started
  instance cannot be claimed by a scanner that found the port.
* The setup token is only valid for five minutes.

*Source:* <https://docs.portainer.io/faqs/installing/setup-token>.

### 6.4 Ports

| Port | Purpose | Exposed here? |
| --- | --- | --- |
| 9443 | UI and API (TLS) | Loopback only, fronted by Caddy on 443 |
| 443 | TLS, all public hostnames | Yes, via Caddy |
| 80 | ACME HTTP-01 challenge + HTTP→HTTPS redirect | Yes, via Caddy |
| 22 | SSH | Yes |
| 8000 | TCP tunnel for Edge Agents | **No** — not needed without Edge Compute |
| 9000 | Legacy HTTP UI | **No** — Portainer itself frames this as legacy |
| 9001 | Portainer Agent | **No** — no Agent is deployed |

*Source:* <https://docs.portainer.io/start/requirements-and-prerequisites>.

### 6.5 Caddy in front

Caddy obtains a Let's Encrypt certificate over the ACME HTTP-01 challenge and
renews it automatically. Portainer serves 9443 with a self-signed certificate,
so the proxy hop uses `tls_insecure_skip_verify`. That is acceptable because
the hop never leaves the host; the public session is still fully verified by
the browser.

HSTS, `X-Content-Type-Options` and `Referrer-Policy` are set, and the
`Server` header is removed.

*Source:* <https://caddyserver.com/docs/automatic-https>.

### 6.6 Secrets live in files, never in the configuration

Every secret on these machines lives in `secrets/` in the repository checkout
(mode 0700, files 0600), and the Nix configuration holds only the **path**:

| Secret | Mechanism | Notes |
| --- | --- | --- |
| Portainer setup token | `docker run --env-file <checkout>/secrets/portainer.env` | Rendered by `virtualisation.oci-containers.containers.<name>.environmentFiles`. |
| Caddy environment | `EnvironmentFile=-<checkout>/secrets/caddy.env` | The `-` prefix makes it optional; systemd ignores a missing file. |

The path is written in the configuration **relative to the checkout**, never
as an absolute path. The checkout root itself is resolved at evaluation time
and exported by `scripts/rebuild.sh` as `NIX_VPS_ROOT`, so the same
configuration works wherever the repository is cloned. The Portainer
administrator account is created by you in the browser during the first-run
setup. The configuration never holds its credentials.

Three properties follow from this:

1. **Nothing enters the Nix store.** The store is world-readable, so a secret
   written into it is a secret published. A path is not. The secret files are
   gitignored, and the flake is evaluated from the *tracked* tree
   (`git+file://`), so they are never copied into the store at all.
   `scripts/rebuild.sh` refuses to run if any file in the secrets directory is
   tracked by git, which is the one way they could get in.
2. **Nothing appears on the command line.** `docker run --env-file` keeps the
   value out of `ps` and out of the systemd unit file. The alternative,
   `environment = { KEY = "value"; }`, renders `-e KEY=value` and leaks into
   both.
3. **Nothing is in git.** The files are created on the machine by
   `scripts/init-secrets.sh` and are not tracked.

**One residual exposure, stated plainly:** an environment variable inside a
container is visible to anyone who can read that container's environment —
`docker inspect` shows it. In practice that means root and Portainer itself,
because Portainer holds the Docker socket. If that matters for a particular
secret, use `LoadCredential` instead, which exposes the file at
`/run/credentials/<unit>/<name>` to the service and nothing else:

```nix
systemd.services.example.serviceConfig.LoadCredential = [ "token:<checkout>/secrets/token" ];
```

**Portainer's own flags, from its source** (`api/cli/cli.go`):

* `PORTAINER_SETUP_TOKEN` and `PORTAINER_NO_SETUP_TOKEN` are read from the
  environment, which is why the setup token can come from an env file.
* The administrator account name is always `admin`.
* The account's credentials are set during the first-run setup in the browser.
  They are never written to a file this configuration manages.

*Source:* <https://github.com/portainer/portainer/blob/develop/api/cli/cli.go>,
<https://github.com/portainer/portainer/blob/develop/api/cmd/portainer/main.go>.

### 6.7 One certificate per hostname, and no wildcards

Each entry in `hostConfig.vhosts` becomes its own Caddy site block, and
therefore its own certificate. Caddy requests a certificate for each hostname
it serves, and any names on another machine are never touched —
certificates are per fully-qualified name, so the two machines do not
interfere.

**There are no wildcard certificates here.** The DNS provider in use has no
public API, so a DNS-01 challenge is not available and only HTTP-01 is. That
means:

* Every hostname in the app zone needs its own DNS A record and its own
  certificate. This is fine for a handful of applications — Let's Encrypt
  allows 50 new certificates per registered domain per week — but it does not
  scale to dozens of names.
* If a wildcard is ever needed, it requires a DNS-01 challenge with an API
  token. The two routes in nixpkgs are:
  * `pkgs.caddy.withPlugins`, with a DNS provider plugin and the provider's
    credentials. The nixpkgs `caddy` package is built with only the standard
    modules, so there is no ready-made `caddy-dns/*` package to start from.
  * NixOS's `security.acme` module, which uses lego and therefore has ~150 DNS
    providers built in, with credentials passed as systemd credentials rather
    than through the Nix store. The resulting certificate is then pointed at
    with `services.caddy.virtualHosts.<name>.useACMEHost`.

The `security.acme` route is usually the less painful one, because the
credentials never enter the world-readable Nix store.

*Source:* <https://github.com/go-acme/lego/blob/master/docs/content/dns/zz_gen_*.md>;
`security.acme.certs.<name>.dnsProvider` and `.credentialFiles` in the nixpkgs
option index.


---

## 7. Nix store, logs, upgrades

### 7.1 Nix

```nix
nix.settings = {
  sandbox = true;                 # the NixOS default, stated explicitly
  auto-optimise-store = true;     # hard-link identical store paths
  trusted-users = [ "root" ];     # only root gets privileged daemon ops
  trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
};
nix.gc = { automatic = true; options = "--delete-older-than 30d"; persistent = true; };
```

`auto-optimise-store` matters on a small VPS disk: it turns duplicate store
paths into hard links.

The `cache.nixos.org` key is the value nixpkgs itself sets — *"By default, only
the key for `cache.nixos.org` is included."* It is restated here to make the
trust boundary explicit.

*Source:* `nixos/modules/config/nix.nix` on `nixos-26.05`.

### 7.2 Logs

```nix
services.journald.extraConfig = ''
  SystemMaxUse=512M
  SystemKeepFree=1G
  MaxRetentionSec=1month
'';
```

Necessary because Docker logs go to the journal (see §5.1). Without a cap, a
chatty application fills the root filesystem — on a VPS with a single ext4
root partition, that takes down everything.

### 7.3 Automatic upgrades are off — on purpose

`system.autoUpgrade.enable = false`.

The auto-upgrade timer runs `nixos-rebuild switch --upgrade`, which resolves
against a **channel**, not against this flake. Enabling it would silently
drift the machine off the pinned configuration and off this repository, which
is exactly the failure mode a declarative configuration exists to prevent.

The supported procedure is `nix flake update` followed by an explicit
`./scripts/rebuild.sh`, which is reviewable in a diff. It is
documented in `DEPLOY.md`.

The trade-off is real and worth stating: **security patches are not applied
automatically.** On a machine exposed to the internet, run the update procedure
monthly at minimum.

---

## 8. Accepted risks

These are known, deliberate, and not fixed by this configuration.

1. **Portainer is root-equivalent.** It holds the Docker socket by design.
   Mitigation: TLS only, setup token, a strong administrator credential, and
   treat a Portainer compromise as a host compromise.
2. **`docker.sock` inside a container is root-equivalent for anything Portainer
   launches.** A container with the socket mounted can do the same thing.
3. **The `docker` group is empty, but root has unrestricted access**, and root
   login is open until you complete the lockdown procedure in `DEPLOY.md`.
4. **No MAC layer.** AppArmor is not integrated enough to rely on, and SELinux
   is not integrated at all.
5. **Container images are third-party.** `no-new-privileges` and `icc=false`
   reduce the blast radius, but a malicious image running as root inside its
   container is still a risk. Only run images you trust.
6. **No automatic security updates.** See §7.3.
7. **Strict reverse-path filtering could drop traffic** if the provider's
   network turns out to be asymmetric. The escape hatch is in §2.4.
8. **The NixOS firewall does not gate container ports.** Every application you
   deploy must publish on loopback and go through a proxy.
9. **Kernel module lockdown can surprise you** when you need a module that was
   not anticipated. See §4.3.

---

## 9. Option-name traps

Options that are commonly cited but do **not** exist in nixpkgs, or whose real
name differs. Each was checked against the 26.05 option index:

| Common belief | Reality |
| --- | --- |
| `security.firewall` | Does not exist. It is `networking.firewall`. |
| `networking.firewall.logChanges` | Does not exist. `logRefusedConnections` / `logRefusedPackets`. |
| `networking.firewall.forwardPorts` | Does not exist. `filterForward` (nftables backend only). |
| `virtualisation.docker.openFirewall` | Does not exist. nixpkgs opens no ports for Docker. |
| `virtualisation.docker.portBindings` | Does not exist. Ports live in the container definition. |
| `virtualisation.docker.daemonSettings` | Does not exist. It is `daemon.settings`. |
| `virtualisation.docker.prune` | Does not exist. It is `autoPrune.*`. |
| `virtualisation.docker.allowedRegistries` / `allowedUsers` | Do not exist. |
| `services.fail2ban.settings` | Does not exist. It is `daemonSettings` and `jails.<name>.settings`. |
| `boot.initrd.systemd.enable` | Removed. The initrd is systemd-based now. |
| `security.patches`, `security.rngseed`, `security.privileges`, `security.rekernel`, `security.protectedSysctl`, `security.denyNewPrivileges`, `security.suid` | None of these exist. |
| `services.monitoring` | Does not exist. Use `services.prometheus`. |
| `nix.build-users-group`, `nix.path-info` | Do not exist. |
| `security.sudo-rs.*` | Present on unstable; **not confirmed** on 26.05, so not used. |
