# NixOS VPS — Security Hardening, Docker and Portainer

**Research document.** Primary sources only. Every NixOS option listed in
[§8 Verified Option Reference](#8-verified-option-reference) was resolved against the
live official option index for the `nixos-unstable` branch and, where the option's
semantics mattered, against the nixpkgs module source on `nixos-unstable`.
Options that could **not** be verified are listed in
[§10 Unverified / Commonly Repeated But Unsourced](#10-unverified--commonly-repeated-but-unsourced)
and are **not** included in the reference table.

> **Target platform.** The configuration in this repository targets **NixOS
> 26.05** (current stable), not unstable. Everything the implementation
> actually uses was re-verified against the `nixos-26.05` branch; see
> [§2.2 Re-verification against the stable 26.05 branch](#22-re-verification-against-the-stable-2605-branch)
> for the resolution of the stable-channel caveats listed in §2.1 and for the
> three implementation deltas that resulted. The full §8 table remains a
> `nixos-unstable` snapshot and has **not** been re-verified option by option
> against 26.05.

**Scale:** §8 lists **335 distinct NixOS option paths** across 290 table rows
(§8.1–§8.7), plus 9 explicitly-labelled *freeform* entries whose individual keys
are accepted but not indexed. A further **28 option paths are explicitly recorded
as NOT FOUND** (§4.2), and 2 more are recorded as *accepted but unindexed*
(freeform parents).

No configuration code is presented here — this document is the research that
precedes writing one.

---

## 1. Method and source policy

| Requirement | How it was met |
| --- | --- |
| NixOS option facts | `nixos` MCP server (`search.nixos.org` live index) + nixpkgs `nixos-unstable` module source on GitHub |
| NixOS prose / workflow | `nixos.org/manual/nixos/unstable` (official Manual) |
| NixOS first-party advice | `wiki.nixos.org` (official NixOS Wiki — first-party) |
| Nix CLI semantics | `nixos.org/manual/nix/stable` (official Nix Manual) |
| Docker Engine | `docs.docker.com` (official) + `github.com/portainer/portainer` (official upstream repo) |
| Portainer | `docs.portainer.io` (official) + `github.com/portainer/portainer` releases |
| systemd hardening | `man7.org` reproduction of `systemd.exec(5)` / `systemd.resource-control(5)` (upstream man pages) |

Deliberately **excluded** as authorities: blogs, Medium, Reddit, DevOps tutorial
sites, hardening listicles. Where a widely-repeated practice could not be tied to a
primary source it appears in §10, explicitly labelled.

**One important caveat on option existence.** The search index exposes *declared*
options. Several options used in practice are **freeform submodules** whose
sub-keys are not individually declared — for example `services.openssh.settings` is
an open submodule with `freeformType = settingsFormat.type`
([sshd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ssh/sshd.nix)),
so `services.openssh.settings.MaxAuthTries` is **accepted and rendered into
`sshd_config`** even though a lookup for it returns "not found". These are called
out explicitly in §8 under "freeform" rows and in §11.

---

## 2. Version Context

Findings were verified against **nixpkgs `nixos-unstable`** (branch HEAD
`31ecbaca1bdefa45dffc409f0250bd8039ea0010` at time of research; indexed revision
`latest-52-nixos-unstable`). The Manual consulted is the *unstable* edition
(`nixos.org/manual/nixos/unstable`).

The host brief says "unstable (26.11)". **This does not match the official channel
table.** The live channel index reports:

| Channel | Branch | Status |
| --- | --- | --- |
| 25.11 | `nixos-25.11` | previous stable |
| **26.05** | `nixos-26.05` | **current stable** (`stable` → 26.05, `beta` → 26.05) |
| unstable | `nixos-unstable` | development |

There is no `26.11` channel in the official index. `nixos-unstable` is the
development branch that will *become* a future stable release (26.11 is a
plausible *next* release number for that branch, but it is not a channel you can
pin today). Everything below is therefore "as of `nixos-unstable` on 2026-10-30".

### 2.1 Options that may not exist on stable 26.05 / 25.11

The Manual states of unstable: *"This corresponds to NixOS's main development
branch, and may thus see radical changes between channel updates. It's not
recommended for production systems."*
([NixOS Manual, Upgrading NixOS](https://nixos.org/manual/nixos/unstable/#sec-changing-config))

Items verified only on unstable, or known to be unstable-only:

| Item | Status on stable | Evidence |
| --- | --- | --- |
| `nixos-rebuild` implemented as `nixos-rebuild-ng` (Python) with `dry-build`, `dry-activate`, `list-generations`, `--target-host`, `--elevate {none,sudo,run0}`, `--specialisation` | **Unstable-first.** The `nixos-rebuild-ng` package lives at `pkgs/by-name/ni/nixos-rebuild-ng/` and its man page is the one cited here | [`nixos-rebuild.8.scd`](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd) |
| `security.sudo-rs.*` (memory-safe sudo: `security.sudo-rs.enable`, `.extraRules`, `.execWheelOnly`, `.configFile`, `.package`) | Present on unstable; **not confirmed** on 26.05/25.11 | `search.nixos.org` options index, unstable |
| `services.openssh.settings.KbdInteractiveAuthentication` | Present on unstable; the module keeps `mkAliasOptionModule` shims for the removed `services.openssh.kbdInteractiveAuthentication` and `challengeResponseAuthentication`, which indicates recent migration | [sshd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ssh/sshd.nix) |
| `boot.initrd.systemd.network.wait-online.*` | Initrd is systemd-based on unstable; the scripted initrd (`boot.initrd.systemd.enable`) has been **removed** (§3.3) | [initrd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/initrd.nix) |
| `networking.firewall.backend` (`"iptables" \| "nftables" \| "firewalld"`) and the `firewalld` backend | Present on unstable; **not confirmed** on 26.05 | options index |
| `networking.firewall.extraInputRules` / `extraForwardRules` / `extraReversePathFilterRules` (nftables-only) | nftables-era options; present on unstable | options index |
| `systemd.services.<name>.confinement.*` (`enable`, `mode`, `packages`, `fullUnit`, `binSh`) | Present on unstable | options index |
| `systemd.network.networks.<name>.<section>Config` (per-section: `bridgeConfig`, `canConfig`, `cakeConfig`, …) | Present on unstable | [network-interfaces-systemd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/tasks/network-interfaces-systemd.nix) |
| `services.logind.settings.Login.KillUserProcesses` default `false` | The non-default is a **nixpkgs-specific override** of the systemd default; documented as such | options index |

Everything else in the reference table is long-standing and expected to exist on
stable, but **was not individually re-verified against 26.05** — that is an
explicit gap (see §11).

### 2.2 Re-verification against the stable 26.05 branch

The target platform was subsequently pinned to **NixOS 26.05** (current stable),
nixpkgs revision `6f06d204d8f2d8761d9da78778745974a3216381` (branch
`nixos-26.05`), and the findings were re-checked against that branch's live
option index and module source while the configuration in this repository was
written.

**Resolution of the §2.1 cautions**

| Item | Status on 26.05 | Evidence |
| --- | --- | --- |
| `networking.firewall.backend` (`"iptables" \| "nftables" \| "firewalld"`) | **Exists.** Type and default confirmed: `"firewalld"` if `services.firewalld.enable`, else `"nftables"` if `networking.nftables.enable`, else `"iptables"`. | `networking.firewall.backend`, 26.05 option index |
| `security.sudo-rs.*` (`enable`, `extraRules`, `execWheelOnly`, `configFile`, `defaultOptions`) | **Exists.** The whole namespace is present on 26.05, not only on unstable. Not used in this configuration, because the VPS's admin model is root-only and `sudo-rs` would change how escalation works. | `security.sudo-rs.*`, 26.05 option index |
| `services.openssh.settings.KbdInteractiveAuthentication` | **Accepted** on 26.05 as a freeform `sshd_config` key; the generated `sshd_config` contains `KbdInteractiveAuthentication yes`. The `mkAliasOptionModule` shims for the removed `services.openssh.kbdInteractiveAuthentication` are also present. | 26.05 `nixos/modules/services/networking/ssh/sshd.nix`; generated `sshd_config` |
| `virtualisation.docker.autoPrune.*` | **Exists** on 26.05 (`enable`, `dates`, `flags`, `persistent`, `randomizedDelaySec`, `allVolumes.*`). A lookup for the bare name `autoPrune` returns NOT_FOUND because it is a submodule, not a leaf option — the leaf `autoPrune.enable` is present. | 26.05 option index |
| `virtualisation.docker.rootless.*` | **Exists** on 26.05 (`enable`, `package`, `extraPackages`, `daemon.settings`, `setSocketVariable`). Not enabled; see §5.5 and the accepted-risks list. | 26.05 option index |
| `boot.initrd.systemd.enable` | **Still removed.** The initrd is systemd-based on 26.05. | 26.05 `nixos/modules/system/boot/systemd/initrd.nix` |

**Additional facts established during the 26.05 re-verification**

* `virtualisation.docker.daemon.settings.live-restore` defaults to
  `versionOlder config.system.stateVersion "24.11"`, so on `stateVersion =
  "26.05"` it resolves to **false** — the option must be requested explicitly
  to get live restore.
* `virtualisation.docker.logDriver` defaults to `"journald"` on 26.05, not
  upstream's `"json-file"`. The generated `daemon.json` therefore needs no
  `log-opts` rotation; `services.journald.extraConfig` bounds the space
  instead.
* `services.fail2ban.jails.<name>` is a submodule with an `enabled` option
  defaulting to `true`. The `sshd` jail exists because the module instantiates
  `services.fail2ban.jails.sshd.settings.port` whenever
  `services.openssh.enable` is true, and the jail's `enabled` option then
  defaults to `true` — the jail does **not** need to be declared by hand. The
  fail2ban module also sets `services.openssh.settings.LogLevel` to `VERBOSE`
  when fail2ban is enabled.
* `services.caddy.openFirewall` defaults to **false**; it is not opened
  implicitly. It opens TCP `httpPort` (80) and TCP+UDP `httpsPort` (443).
* `services.journald.*` is the namespace; there is no `systemd.journald.*`.
  `services.journald.extraConfig` is the supported way to set `SystemMaxUse`
  and friends.
* `nix.gc.options`, `nix.gc.persistent` and `nix.settings.auto-optimise-store`
  all exist on 26.05 with the semantics assumed in §8.4.
* `security.lockKernelModules` exists on 26.05 and is implemented by the
  `disable-kernel-module-loading.service` unit, which runs after
  `systemd-modules-load.service` and `multi-user.target`. It requires a reboot
  to take effect.

**Deltas that changed the implementation**

1. `virtualisation.docker.daemon.settings` is the correct option name on
   26.05 (confirmed), and the generated `daemon.json` contains exactly
   `group`, `hosts`, `log-driver`, `storage-driver` plus the operator's keys.
2. The Docker daemon unit is installed from the `moby` package and the nixpkgs
   module's `ExecStart` is applied as a **drop-in**
   (`/etc/systemd/system/docker.service.d/overrides.conf`) that resets
   `ExecStart=` and re-sets it with `--config-file=<store path>`. The
   `--config-file` is therefore present in the effective unit, even though the
   packaged unit's own `ExecStart` is still visible in the main unit file.
3. `services.caddy` ships its unit from the upstream `caddyserver/dist`
   package, which carries `AmbientCapabilities=CAP_NET_ADMIN
   CAP_NET_BIND_SERVICE`. The nixpkgs module's settings are applied as a
   drop-in, so the ambient capabilities survive and Caddy can bind ports 80
   and 443 as the unprivileged `caddy` user.

---

## 3. NixOS VPS Baseline

### 3.1 Flake structure and the rebuild workflow

**Primary source for the modern CLI:** the `nixos-rebuild` man page shipped in
nixpkgs — [`pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd`](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd)
(branch `nixos-unstable`).

Verified facts:

* The configuration is read from `/etc/nixos/configuration.nix`, `/etc/nixos/flake.nix`,
  `/etc/nixos/system.nix`, or the file/attribute given by `--file` / `--attr` / `--flake`.
* **`--flake <flake-uri>[#name]`** builds from a flake. It **defaults to the directory
  containing the symlink `/etc/nixos/flake.nix`** if that exists. The flake **must
  contain an output named `nixosConfigurations.<name>`**; if `#name` is omitted it
  defaults to the current host name.
* `/etc/nixos/flake.nix` **may itself be a symlink** into the real flake repo, so
  `/etc/nixos` need not be a flake.
* `--no-flake` disables implicit flake detection.
* `--accept-flake-config` is required to honour a flake's `nixConfig` beyond the
  safe subset. The Nix Manual enumerates that safe subset: `bash-prompt`,
  `bash-prompt-prefix`, `bash-prompt-suffix`, `flake-registry`,
  `commit-lock-file-summary` — *"only a small set of options is allowed to be set
  without confirmation so long as accept-flake-config is not enabled"*
  ([Nix Manual, Flakes](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html)).
* Actions: `switch`, `boot`, `test`, `build`, `edit`, `repl`, `dry-build`,
  `dry-activate`, `build-image`, `build-vm`, `build-vm-with-bootloader`,
  `list-generations`.
  * `switch` — build, activate, **and** make boot default.
  * `boot` — build and make boot default, **do not activate**; takes effect next reboot.
  * `test` — build and activate, **but do not** add to the boot menu; a reboot
    reverts to the last `switch`/`boot` generation.
* `--profile-name <name>` / `-p` — separate boot-menu submenu per profile.
* `--specialisation <name>` / `-c` — activate a specialisation.
* `--rollback` — roll back to the previous configuration in
  `/nix/var/nix/profiles/system`.
* `--target-host <host>` / `--build-host <host>` — remote build/deploy over SSH.
  Activation for `switch`/`boot`/`test` needs root on the target.
* `--elevate {none,sudo,run0}` — privilege elevation. `run0` uses systemd's
  polkit-based elevation and requires `system.tools.nixos-rebuild.enableRun0Elevation = true`
  on the target.
* `--no-reexec` — disables the default behaviour of rebuilding `nixos-rebuild`
  itself from `config.system.build.nixos-rebuild` of the current channel/flake and
  re-exec'ing into it.
* `--store-path <path>` — deploy a pre-built system closure; mutually exclusive with
  `--rollback`, `--flake`, `--file`, `--attr`; only valid with `switch`, `boot`,
  `test`, `dry-activate`.
* `--upgrade` / `--upgrade-all` — update the root user's `nixos` channel before rebuilding.
* `--install-bootloader` — reinstall the bootloader.

The classic Manual text agrees on the action semantics and adds the warning that
`nixos-rebuild` *"doesn't start/stop user services automatically"* and that the
commands *"must be executed as root"*
([NixOS Manual, Changing the Configuration](https://nixos.org/manual/nixos/unstable/#sec-changing-config)).

**`nixosConfigurations` / `nixosModules` as flake outputs** are provided by nixpkgs
itself — [`nixpkgs/flake.nix`](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/flake.nix)
defines `nixosConfigurations` and `nixosModules` outputs. The `nixosConfigurations`
output shape and `nixpkgs.lib.nixosSystem` are nixpkgs API, not Nix Manual API.

**Recommended dev workflow, synthesised from the above:**

1. Edit the flake in git; commit.
2. `nixos-rebuild build --flake .#<host>` — compile-only, no root needed.
3. `nixos-rebuild build-vm --flake .#<host>` then `./result/bin/run-<host>-vm` —
   validate in a throwaway VM. Note the Manual's caveat: the VM has none of the
   host's data or home directories unless `users.mutableUsers = false`.
4. `nixos-rebuild test --flake .#<host>` — activate without changing the boot default
   (a reboot reverts).
5. `nixos-rebuild switch --flake .#<host>` — activate and set as boot default.
6. Use `--profile-name staging` to keep production and test profiles in separate
   GRUB submenus.

**`buildUsers`:** the Manual describes NixOS as automatically installed in
multi-user mode with *"build users which nix operations are delegated to"*
([NixOS Wiki, Security](https://wiki.nixos.org/wiki/Security)). The delegation
mechanism is `nix.settings` + `nix.build-users-group`/`nix.nrBuildUsers`, but
**`nix.build-users-group` is not a NixOS option on unstable** (see §10) — the
module computes `nix.nrBuildUsers` itself.

### 3.2 Filesystem layout for a VPS

`fileSystems` — *attribute set of (submodule)*, default `{}`. Must include a
`"/"` entry. Each entry has `mountPoint`, `device` (or `label`), `fsType`, and
`options` (default `[ "defaults" ]`). Elements are attribute sets, so
`fileSystems."/".device = "/dev/vda1"` works.

* **ext4**: `fsType = "ext4"`. The Manual's own example uses
  `fsType = "ext4"` with `options = [ "rw" "data=ordered" "relatime" ]`.
* **ZFS**: requires `boot.zfs.enabled = true` and `boot.zfs.package`. Root pools
  can be encrypted via `boot.zfs.requestEncryptionCredentials` (boolean or list of
  dataset names; *"For root pools the encryption key can be supplied both an
  interactive prompt (keylocation=prompt) and from a file (keylocation=file://)"*)
  and via TPM-backed `boot.zfs.tzpfms.enable`.
  **Do not enable `boot.zfs.forceImportRoot` / `boot.zfs.forceImportAll`** — the
  option descriptions explicitly say *"It is highly recommended to keep this option
  disabled as it bypasses ZFS safeguard that protect your pools."*
* **LUKS**: the Wiki lists LUKS partition-level disk encryption as supported on
  NixOS ([NixOS Wiki, Security](https://wiki.nixos.org/wiki/Security)).

**Security note on ZFS vs ext4** — this is *not* a primary-source-backed claim
about relative security. What *is* primary-source-backed:

* Docker's `storage-driver` interacts with the host filesystem, and nixpkgs'
  `virtualisation.docker.storageDriver` enum includes `"zfs"` alongside
  `"btrfs"`, `"overlay2"`, etc.
* nixpkgs explicitly adds `config.boot.zfs.package` to the docker service's `path`
  **only when** `virtualisation.docker.storageDriver == "zfs"`
  ([docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix)).
* nixpkgs warns: *"Changing the storage driver will cause any existing containers
  and images to become inaccessible."*
* `security.lockKernelModules` is incompatible with loading modules late — *"Problems
  caused by delayed module loading can be fixed by adding the module(s) in question
  to `boot.kernelModules`."*

**Recommendation grounded in those facts:** on a VPS, prefer **ext4** for the root
filesystem and **ZFS only for a separate data pool** if snapshots are needed, and
keep `boot.zfs.enabled` off unless a ZFS pool is actually used — because enabling it
pulls ZFS into the boot path and interacts with the Docker storage-driver logic.

### 3.3 Boot loader, initrd, swap

* `boot.loader.grub.enable` — boolean, default `!config.boot.isContainer`.
  `boot.loader.grub.devices` — list of string, default `[]`; the Manual shows
  `/dev/disk/by-id/wwn-0x...` form.
* `boot.loader.systemd-boot.enable` — boolean, default `false`. The option text
  points at the systemd-boot upstream docs. **GRUB is the default for a VPS**;
  systemd-boot requires EFI and is not the right default for most VPS providers.
* **Initrd:** `boot.initrd.systemd.enable` has been **REMOVED** on unstable.
  Source, `nixos/modules/system/boot/systemd/initrd.nix`:
  ```nix
  (lib.mkRemovedOptionModule [ "boot" "initrd" "systemd" "enable" ] ''
    Scripted initrd has been removed.
  '')
  ```
  The initrd is systemd-based; `boot.initrd.systemd` is now a set of *content*
  options (`contents`, `groups`, `mounts`, `automounts`, `network`,
  `network.wait-online.*`, `shell.enable`, `emergencyAccess`, `fido2.enable`,
  `dbus.enable`, `dmVerity.enable`, `managerEnvironment`, `initrdBin`, `extraBin`).
  **`boot.initrd.systemd.enable` must not be used.**
* `swapDevices` — list of submodule, default `[]`. Each element is
  `{ device = "/dev/..."; }` or `{ label = "..."; }`. Using a **label is recommended**.
* `zramSwap.enable` — boolean (top-level `zramSwap`, not under a namespace).
  Companion options: `zramSwap.algorithm` (default `zstd`? — see §8), `zramSwap.memoryPercent`,
  `zramSwap.memoryMax`, `zramSwap.swapDevices` (*"Number of zram devices to be used
  as swap, recommended is 1"*), `zramSwap.priority`, `zramSwap.writebackDevice`.
  `zramSwap.priority` should exceed any disk swap priority.
* `boot.kernelParams` — list of string, default `[]`. The NixOS Wiki's hardening
  page gives the canonical set: `"slab_nomerge"`, `"page_poison=1"`,
  `"page_alloc.shuffle=1"`, `"debugfs=off"`
  ([NixOS Wiki, NixOS Hardening](https://wiki.nixos.org/wiki/NixOS_Hardening)).
* `boot.kernelPatches` — list of attribute set, default `[]`. Each element:
  `name` (required), `patch` (path or derivation, may be null),
  `structuredExtraConfig` (attrset without the `CONFIG_` prefix),
  `features`, and deprecated `extraConfig`. Pre-made patches live in `pkgs.kernelPatches`.
* `boot.kernelModules` — *(attribute set of boolean) or (list of string)*, default `{}`.
* `boot.blacklistedKernelModules` — *(attribute set of boolean) or (list of string)*, default `{}`.

### 3.4 `system.stateVersion` — what it actually means

**Primary source:** the option description itself (options index) and the NixOS
Manual's "State revision" section.

> *"This option defines the first version of NixOS you have installed on this
> particular machine, and is used to maintain compatibility with application data
> (e.g. databases) created on older NixOS versions. […] Most users should never
> change this value after the initial install, for any reason, even if you've
> upgraded your system to a new NixOS release. **This value does not affect the
> Nixpkgs version your packages and OS are pulled from, so changing this will not
> upgrade your system.** This value being lower than the current NixOS release
> does not mean your system is out of date, out of support, or vulnerable."*
> — `system.stateVersion`

Critical corollary from the Manual: *"Module authors are discouraged from adding
new uses of `system.stateVersion` to their module. However, when the alternatives
are impractical, modules that wish to consume `system.stateVersion` should instead
define their own `stateRevision` option."* And: *"There should be no uses of
`config.system.stateVersion` in the module."* The Manual also distinguishes the two
names: `system.stateVersion` takes a `"YY.MM"`-shaped string; a `stateRevision`
option takes a non-negative integer.

**Practical consequences:**

* Setting `system.stateVersion = "26.05"` on a fresh unstable install does **not**
  pin your packages — it only selects legacy data-format defaults for a handful of
  services.
* **Never bump it** on an existing server without reading the module's release
  notes for the target version. The Manual's release notes show real migrations
  gated on it, e.g. Tandoor Recipes: *"Tandoor Recipes installations initialized
  with `system.stateVersion < 26.05` may suffer from a security vulnerability"*
  (GHSA-g8w3-p77x-mmxh), remediated by moving the media directory and setting
  `services.tandoor-recipes.extraConfig.MEDIA_ROOT`.
* **Security angle:** the fact that `stateVersion` gates *format* defaults means
  bumping it can change on-disk behaviour (and, as above, can be a security
  remediation). Treat "bump stateVersion" as a **migration task with its own
  review**, not a routine upgrade.

### 3.5 Users, SSH, and login

* `users.users` — attribute set of submodule, default `{}`. Per-user options
  verified in the module source (`nixos/modules/config/users-groups.nix`):
  `description`, `uid`, `isNormalUser`, `group`, `extraGroups`, `home`, `shell`,
  `createHome`, the credential options (the plain and hashed forms, the
  file-based form and their `initial` variants), `gid`, and the `openssh`
  submodule.
* `users.users.<name>.openssh.authorizedKeys.keys` — list of string.
* `users.users.<name>.openssh.authorizedKeys.keyFiles` — list of path.
* `users.users.<name>.openssh.authorizedPrincipals` — list of string.
* `users.groups` — attribute set of submodule, default `{}`.
* `users.mutableUsers` — boolean, **default `true`**. When `true`, the system user
  and group databases are **merged** with the declarative `users.users` / `users.groups` on
  activation, and *"existing credentials will not be changed."* When `false`, those
  files are **replaced** wholesale and *"all changed credentials will be reset
  according to the `users.users` configuration on activation."*
  **Security consequence:** with `mutableUsers = false` an imperative credential
  change is reverted on the next activation. With `mutableUsers = true`, imperative `useradd`
  persists but the system is no longer fully declarative.
* An escape hatch on that assertion — boolean, default `false`. *"Disable checking
  that at least the root user or a user in the wheel group can log in using a
  credential or an SSH key. WARNING: enabling this can lock you out of your
  system."*
  NixOS asserts at build time that *"Neither the root account nor any wheel user
  has a credential or SSH authorized key"* unless this is set.

#### `services.openssh`

* `services.openssh.enable` — boolean.
* `services.openssh.ports` — list of 16-bit unsigned integer.
* `services.openssh.openFirewall` — boolean, default `true` (opens the SSH ports in
  the NixOS firewall).
* `services.openssh.settings` — **open submodule** (freeform) of
  `attribute set of (atom (null, bool, int, float or string))`, *"Configuration for
  `sshd_config(5)`."* Declared keys include:
  * `settings.PermitRootLogin` — null or one of the values sshd accepts for
    that directive; **default is the strict one**, which lets root sign in
    with a key only (already strict, so it is not set explicitly here).
  * `settings.X11Forwarding` — null or boolean, **default `false`** (already off).
  * `settings.LogLevel` — null or one of `QUIET…DEBUG3`.
  * `settings.UsePAM` — null or boolean.
  * `settings.KbdInteractiveAuthentication` — null or boolean.
  * `settings.AllowUsers` / `DenyUsers` / `AllowGroups` / `DenyGroups` — null or list of string.
  * `settings.AcceptEnv`, `Ciphers`, `KexAlgorithms`, `Macs`, `GatewayPorts`,
    `Banner`, `ModuliFile`, `StrictModes`, `UseDns`, `PrintMotd`,
    `AuthorizedPrincipalsFile`.
  * Any **other** `sshd_config(5)` key is accepted through the freeform type — e.g.
    `MaxAuthTries`, `LoginGraceTime`, `ClientAliveInterval`, `AllowTcpForwarding`.
    These are **not indexed** (see §11).
* `services.openssh.enableRecommendedAlgorithms` — boolean. *"Use algorithms curated
  and recommended by NixOS. Set to false to use upstream's default algorithms."*
* `services.openssh.authorizedKeysFiles` — list of string, default `[]`. *"These are
  paths relative to the host root file system or home directories and they are
  subject to certain token expansion rules."*
* `services.openssh.authorizedKeysInHomedir` — boolean. When `false`, *"the only files
  trusted by default are those in `/etc/ssh/authorized_keys.d`"*.
* `services.openssh.authorizedKeysCommand` — string. *"The program must be owned by
  root, not writable by group or others and specified by an absolute path."*
* `services.openssh.authorizedKeysCommandUser` — string. *"It is recommended to use a
  dedicated user that has no other role on the host than running authorized keys
  commands."*
* `services.openssh.hostKeys` — list of attribute set.
* `services.openssh.generateHostKeys` — boolean.
* `services.openssh.listenAddresses.<addr>.addr` / `.port` — listen-address pinning.
* `services.openssh.startWhenNeeded` — boolean, **default `false`**. *"If set, sshd is
  socket-activated; that is, instead of having it permanently running as a daemon,
  systemd will start an instance for each incoming connection."* This is the
  socket-activation hardening option.
* `services.openssh.extraConfig` — strings concatenated with `\n`. Verbatim `sshd_config` contents.

### 3.6 The Nix trust model

`nix.settings` is an **open submodule** of
`attribute set of (Nix config atom (null, bool, int, float, str, path or package) or list of …)`,
default `{}`. *"Nix configurations defined under `nix.*` will be translated and
applied to this option."* The module's `legacyConfMappings` table maps legacy
top-level options to `nix.conf` keys:

```
useSandbox            → sandbox
buildCores            → cores
maxJobs               → max-jobs
sandboxPaths          → extra-sandbox-paths
binaryCaches          → substituters
trustedBinaryCaches   → trusted-substituters
binaryCachePublicKeys → trusted-public-keys
autoOptimiseStore     → auto-optimise-store
requireSignedBinaryCaches → require-sigs
trustedUsers          → trusted-users
allowedUsers          → allowed-users
systemFeatures        → system-features
```

Verified `nix.settings` options with their **actual defaults** (from
`nixos/modules/config/nix.nix`):

| Option | Type | Default |
| --- | --- | --- |
| `nix.settings.trusted-users` | list of string | `["root"]` |
| `nix.settings.trusted-public-keys` | list of string | `["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="]` |
| `nix.settings.substituters` | list of string | `["https://cache.nixos.org/"]` |
| `nix.settings.allowed-users` | list of string | `["*"]` |
| `nix.settings.sandbox` | boolean or `"relaxed"` | `true` |
| `nix.settings.require-sigs` | boolean | `true` |
| `nix.settings.auto-optimise-store` | boolean | `false` |
| `nix.settings.max-jobs` | signed integer or `"auto"` | `"auto"` |
| `nix.settings.cores` | signed integer | (unset) |
| `nix.settings.extra-sandbox-paths` | list of string | `[]` |
| `nix.settings.trusted-substituters` | list of string | `[]` |
| `nix.settings.experimental-features` | list of string | `[]` |
| `nix.settings.system-features` | list of string | `["nixos-test" "benchmark" "big-parallel" "kvm" "gccarch-<arch>"]` |

Semantics worth quoting:

* `trusted-users` — *"A list of names of users that have additional rights when
  connecting to the Nix daemon, such as the ability to specify additional binary
  caches, or to import unsigned NARs."* **Trusted users are effectively root on the
  machine** — the `nixos-rebuild` man page confirms this is required for remote
  builders (*"the user executing nixos-rebuild (usually root) to be configured as a
  trusted user in the Nix daemon"*).
* `allowed-users` — *"A list of names of users (separated by whitespace) that are
  allowed to connect to the Nix daemon. […] The default is `*`."* The NixOS Wiki
  hardening page recommends narrowing this to `nix.settings.allowed-users = [ "@users" ]`
  — *"This option allows only `users` group to connect to the Nix daemon."*
* `sandbox` — *"performs builds in a sandboxed environment […] This prevents
  impurities in builds by disallowing access to dependencies outside of the Nix store
  by using network and mount namespaces in a chroot environment."* `"relaxed"`
  *"permits derivations that set `__noChroot = true` to run outside of the sandboxed
  environment."*
* `require-sigs` — *"Nix will only download binaries from binary caches if they are
  cryptographically signed with any of the keys listed in `nix.settings.trusted-public-keys`."*
* `auto-optimise-store` — *"Nix automatically detects files in the store that have
  identical contents, and replaces them with hard links to a single copy."*
  **Default `false`.** Note the trade-off: hard-linking identical store files is a
  *disk-space* optimisation; on a NixOS system the store is already content-addressed
  and heavily deduplicated, so this mainly adds I/O and inode pressure. The
  NixOS Wiki does not list it as a hardening measure. See §10.
* `nix.package` — package. Pinning the Nix version itself.
* `nix.registry` — attribute set of submodule; *"A system-wide flake registry."*
* `nix.build-users-group` — **does not exist** (§10). The module derives
  `nix.nrBuildUsers` itself.

### 3.7 GC and store optimisation

* `nix.gc.automatic` — boolean. *"Automatically run the garbage collector at a
  specific time."*
* `nix.gc.dates` — single-line string or list of string (systemd.time(7) calendar
  event). *"For most desktop and server systems a sufficient garbage collection is
  once a week."*
* `nix.gc.options` — single-line string. Options passed to `nix-collect-garbage`.
* `nix.gc.persistent` — boolean, default `true`. Catches up on missed runs.
* `nix.gc.randomizedDelaySec` — single-line string.
* `nix.optimise.automatic` — boolean. *"Automatically run the nix store optimiser at
  a specific time."* (`nix.optimise` is a **submodule**, not a boolean.)
* `nix.optimise.dates`, `nix.optimise.persistent`, `nix.optimise.randomizedDelaySec`.

**`nix.path-info` does not exist** (§10).

---

## 4. Security hardening — the `security.*` module surface, verified

### 4.1 What actually exists

The `security` namespace in nixpkgs is **much smaller** than commonly assumed. The
options that exist and are verified on unstable:

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `security.apparmor.enable` | boolean | `false` | [apparmor.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/apparmor.nix) |
| `security.apparmor.policies` | attribute set of (submodule) | `{}` | ibid. |
| `security.apparmor.policies.<name>.profile` | strings concatenated with `\n` | — | ibid. |
| `security.apparmor.policies.<name>.path` | null or absolute path | — | ibid. |
| `security.apparmor.policies.<name>.state` | `"disable"` \| `"complain"` \| `"enforce"` | — | ibid. |
| `security.apparmor.includes` | attribute set of strings concatenated with `\n` | `{}` | ibid. |
| `security.apparmor.packages` | list of package | `[]` | ibid. |
| `security.apparmor.enableCache` | boolean | `false` | ibid. |
| `security.apparmor.killUnconfinedConfinables` | boolean | `false` | ibid. |
| `security.audit.enable` | `false` \| `true` \| `"lock"` | `false` | [audit.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/audit.nix) |
| `security.audit.rules` | list of string | `[]` | ibid. |
| `security.audit.failureMode` | `"silent"` \| `"printk"` \| `"panic"` | — | ibid. |
| `security.audit.rateLimit` | signed integer | — | ibid. |
| `security.audit.backlogLimit` | signed integer | — | ibid. |
| `security.audit.package` | package | — | ibid. |
| `security.auditd.enable` | boolean | — | [auditd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/auditd.nix) |
| `security.auditd.settings` | open submodule | — | ibid. |
| `security.auditd.plugins.<name>.*` | submodule | — | ibid. |
| `security.pam.enable` | boolean | — | [pam.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/pam.nix) |
| `security.pam.services` | attribute set of (submodule) | `{}` | ibid. |
| `security.pam.services.<name>.enable` | boolean | — | ibid. |
| `security.pam.services.<name>.failDelay.enable` / `.delay` | boolean / signed integer | — | ibid. |
| `security.pam.loginLimits` | list of (submodule) | — | ibid. |
| `security.pam.loginLimits.<i>.domain` / `.type` / `.item` / `.value` | string / enum / string / string-or-int | — | ibid. |
| `security.pam.oath.enable`, `.usersFile`, `.window`, `.digits` | — | — | ibid. |
| `security.pam.p11.enable` | boolean | — | ibid. |
| `security.pam.krb5.enable` | boolean | — | ibid. |
| `security.sudo.enable` | boolean | — | [sudo.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/sudo.nix) |
| `security.sudo.execWheelOnly` | boolean | — | ibid. |
| `security.sudo.defaultOptions` | list of string | — | ibid. |
| `security.sudo.extraRules` | list of (submodule) | — | ibid. |
| `security.sudo.extraRules.<i>.users` / `.groups` / `.commands` / `.runAs` / `.host` | — | — | ibid. |
| `security.sudo.extraConfig` | strings concatenated with `\n` | — | ibid. |
| `security.sudo.configFile` | strings concatenated with `\n` | — | ibid. |
| `security.sudo-rs.enable` | boolean | — | ibid. (memory-safe sudo) |
| `security.sudo-rs.execWheelOnly` | boolean | — | ibid. |
| `security.sudo-rs.extraRules` / `.extraConfig` / `.configFile` / `.package` | — | — | ibid. |
| `security.lockKernelModules` | boolean | — | *Disable kernel module loading once the system is fully initialised. Module loading is disabled until the next reboot.* |
| `security.protectKernelImage` | boolean | — | *Whether to prevent replacing the running kernel image.* |
| `security.allowSimultaneousMultithreading` | boolean | — | *Whether to allow SMT/hyperthreading.* |
| `security.forcePageTableIsolation` | boolean | — | *Whether to force-enable the Page Table Isolation (PTI) Linux kernel feature even on CPU models that claim to be safe from Meltdown.* |
| `security.virtualisation.flushL1DataCache` | null \| `"never"` \| `"cond"` \| `"always"` | `null` | *Whether the hypervisor should flush the L1 data cache before entering guests.* |

The five `security.*` hardening options above (`lockKernelModules`,
`protectKernelImage`, `allowSimultaneousMultithreading`, `forcePageTableIsolation`,
`virtualisation.flushL1DataCache`) are documented with worked examples on the
**NixOS Wiki hardening page** ([NixOS Wiki, NixOS Hardening](https://wiki.nixos.org/wiki/NixOS_Hardening)),
which is first-party.

### 4.2 What does NOT exist (verified absences)

These were explicitly queried and returned **NOT FOUND** against the unstable index:

| Not an option | Reality |
| --- | --- |
| `security.firewall` | The firewall is **`networking.firewall`** (§4.3). |
| `security.firewall.*` | Not present. |
| `security.patches` | No such module. Patches are applied via `boot.kernelPatches` / `nixpkgs.overlays`. |
| `security.rngseed` / `security.rngseed.enable` | Not present. |
| `security.privileges` / `security.privileges.seccompProfiles` | Not present. |
| `security.rekernel` / `security.rekernel.enable` | Not present. |
| `security.protectedSysctl` | Not present. |
| `security.denyNewPrivileges` | Not present. (`NoNewPrivileges` exists only as a **systemd** directive, see §4.6.) |
| `security.suid` | Not present. |
| `security.firewall.allowedTCPPorts` | `networking.firewall.allowedTCPPorts`. |
| `nix.trustedUsers` | `nix.settings.trusted-users` (or the legacy top-level `nix.trustedUsers`, which the module translates — see the `legacyConfMappings` table). |
| `nix.build-users-group` | Not present on unstable. |
| `nix.path-info` | Not present on unstable. |
| `services.monitoring` | Not present. (`services.prometheus.enable` is the real monitoring option.) |
| `services.fail2ban.settings` | The option is **`services.fail2ban.daemonSettings`**. |
| `virtualisation.docker.daemonSettings` | The option is **`virtualisation.docker.daemon.settings`**. |
| `virtualisation.docker.openFirewall` | Not present — Docker does **not** open ports in the NixOS firewall. |
| `virtualisation.docker.portBindings` | Not present — there is no declarative port-mapping option for Docker in NixOS. |
| `virtualisation.docker.allowedRegistries` | Not present. |
| `virtualisation.docker.allowedUsers` | Not present. |
| `virtualisation.docker.prune` | The option is **`virtualisation.docker.autoPrune.*`**. |
| `virtualisation.docker.daemon.settings` `live-restore` alias | `virtualisation.docker.liveRestore` exists as an **alias** module for `daemon.settings.live-restore`. |
| `networking.firewall.logChanges` | The real options are `logRefusedConnections`, `logRefusedPackets`, `logRefusedUnicastsOnly`. |
| `networking.firewall.forwardPorts` | Not present. Use `networking.firewall.filterForward` (nftables) instead. |
| `boot.initrd.systemd.enable` | **Removed** — *"Scripted initrd has been removed."* |
| `systemd.tmpfiles` (as a leaf) | The options are `systemd.tmpfiles.rules`, `.settings`, `.packages`. |
| `users.users.<name>` credential options as *indexed* leaf options | They exist in the module source but are not exposed as indexed leaves by the search API — use them, they work. |
| `services.openssh.settings.MaxAuthTries` | Not a *declared* option, but accepted via the freeform `settings` submodule. |

### 4.3 `networking.firewall` — the real firewall module

**Primary source:** `nixos/modules/services/networking/firewall.nix` + the options
index + the Manual's "Firewall" section.

> *"NixOS has a simple stateful firewall that blocks incoming connections and
> other unexpected packets. The firewall applies to both IPv4 and IPv6 traffic.
> **It is enabled by default.**"*
> — [NixOS Manual, Firewall](https://nixos.org/manual/nixos/unstable/#sec-firewall)

Verified options:

| Option | Type | Default | Notes from the option text |
| --- | --- | --- | --- |
| `networking.firewall.enable` | boolean | `true` | *"blocks connection attempts to unauthorised TCP or UDP ports"* |
| `networking.firewall.allowedTCPPorts` | list of 16-bit uint | `[]` | |
| `networking.firewall.allowedUDPPorts` | list of 16-bit uint | `[]` | |
| `networking.firewall.allowedTCPPortRanges` | list of attrset `{ from; to; }` | `[]` | |
| `networking.firewall.allowedUDPPortRanges` | list of attrset `{ from; to; }` | `[]` | |
| `networking.firewall.interfaces` | attribute set of (submodule) | `{}` | *"Interface-specific open ports."* |
| `networking.firewall.interfaces.<name>.allowedTCPPorts` / `.allowedUDPPorts` / `.allowedTCPPortRanges` / `.allowedUDPPortRanges` | list | `[]` | |
| `networking.firewall.trustedInterfaces` | list of string | `[]` | *"Traffic coming in from these interfaces will be accepted unconditionally. Traffic from the loopback (lo) interface will always be accepted."* |
| `networking.firewall.checkReversePath` | boolean \| `"strict"` \| `"loose"` | — | *"Performs a reverse path filter test on a packet. If a reply to the packet would not be sent via the same interface that the packet arrived on, it is refused."* |
| `networking.firewall.backend` | `"iptables"` \| `"nftables"` \| `"firewalld"` | `iptables` (or `nftables` if `networking.nftables.enable`, or `firewalld` if `services.firewalld.enable`) | |
| `networking.firewall.extraCommands` | strings concatenated with `\n` | `""` | **iptables backend only.** *"executed just before the final 'reject' firewall rule is added"* |
| `networking.firewall.extraPackages` | list of package | `[]` | Packages available to `extraCommands`. |
| `networking.firewall.extraInputRules` | strings concatenated with `\n` | `""` | **nftables backend only.** |
| `networking.firewall.extraForwardRules` | strings concatenated with `\n` | `""` | **nftables backend only.** |
| `networking.firewall.extraReversePathFilterRules` | strings concatenated with `\n` | `""` | **nftables backend only.** |
| `networking.firewall.extraStopCommands` | strings concatenated with `\n` | `""` | **iptables backend only.** |
| `networking.firewall.filterForward` | boolean | `false` | **nftables only.** *"Enable filtering in IP forwarding."* |
| `networking.firewall.logRefusedConnections` | boolean | `false` | Logs to the kernel log (`dmesg` / `journalctl -k`). |
| `networking.firewall.logRefusedPackets` | boolean | `false` | *"This tends to give a lot of log messages, so it's mostly useful for debugging."* |
| `networking.firewall.logRefusedUnicastsOnly` | boolean | `false` | Only log packets specifically directed at this machine. |
| `networking.firewall.logReversePathDrops` | boolean | `false` | Logs rp-filter drops as martians. |
| `networking.firewall.rejectPackets` | boolean | `false` | *"Rejecting packets makes port scanning somewhat easier."* (default is drop) |
| `networking.firewall.allowPing` | boolean | — | *"ICMPv6 pings are always allowed."* |
| `networking.firewall.pingLimit` | null or strings | `null` | |
| `networking.firewall.autoLoadConntrackHelpers` | boolean | `false` | *"Connection tracking is disabled by default."* |
| `networking.firewall.connectionTrackingModules` | list of string | `[]` | *"As helpers can pose as a security risk, it is advised to set this to an empty list."* |
| `networking.firewall.package` | package | — | |

**Firewall interaction with Docker — critical.** The NixOS Manual notes that TCP
port 22 is opened automatically when `services.openssh.enable = true`. It does
**not** do this for Docker: `virtualisation.docker` has **no** `openFirewall`
option. Furthermore `networking.nftables.enable` warns:

> *"Note that if you have Docker enabled you will not be able to use nftables
> without intervention. Docker uses iptables internally to setup NAT for
> containers. This module disables the `ip_tables` kernel module, however Docker
> automatically loads the module."*
> — `networking.nftables.enable`

**Recommendation:** on a Docker host, keep the firewall on the **iptables** backend
(`networking.firewall.backend` default), open only the ports you intend
(22, 443, 9443), and **explicitly** list any container-published port.

**The single most important container networking fact on NixOS** comes from the
`virtualisation.oci-containers` option text:

> *"**Publishing a port bypasses the NixOS firewall.** If the port is not supposed
> to be shared on the network, make sure to publish the port to localhost.
> Example: `127.0.0.1:1234:1234`"*
> — `virtualisation.oci-containers.containers.<name>.ports`

This applies equally to Docker's own `-p` mechanism (Docker inserts its own
DNAT rules ahead of the NixOS firewall's input chain).

### 4.4 `services.fail2ban`

**Primary source:** options index (`nixos/modules/services/networking/fail2ban.nix`).

| Option | Type | Default |
| --- | --- | --- |
| `services.fail2ban.enable` | boolean | `false` |
| `services.fail2ban.jails` | attribute set of (strings concatenated with `\n` or submodule) | — |
| `services.fail2ban.daemonSettings` | attribute set of section of an INI file | — |
| `services.fail2ban.maxretry` | unsigned integer ≥ 0 | — |
| `services.fail2ban.bantime` | string | — |
| `services.fail2ban.ignoreIP` | list of string | — |
| `services.fail2ban.banaction` | string | — |
| `services.fail2ban.banaction-allports` | string | — |
| `services.fail2ban.extraPackages` | list of package | `[]` |
| `services.fail2ban.package` | package | — |
| `services.fail2ban.packageFirewall` | package | *"Defaults to the package for your firewall (iptables or nftables)."* |
| `services.fail2ban.bantime-increment.enable` | boolean | — |
| `services.fail2ban.bantime-increment.factor` / `.formula` / `.maxtime` / `.multipliers` / `.overalljails` / `.rndtime` | — | — |

Key behaviour from the option text:

> *"NixOS comes with a default sshd jail; for it to work well,
> `services.openssh.settings.LogLevel` should be set to `"VERBOSE"` or higher so
> that fail2ban can observe failed login attempts. **This module sets it to
> `"VERBOSE"` if not set otherwise**, so enabling fail2ban can make SSH logs more
> verbose."*

**Interaction with the firewall:** fail2ban's banning actions use
`iptables`/`nftables` directly. Because `networking.firewall.extraCommands` is
**iptables-only** and `extraInputRules` is **nftables-only**, the backend choice
determines which mechanism the rest of the config can use. `services.fail2ban.packageFirewall`
follows `networking.firewall.backend` by default, so the two stay consistent.

`services.fail2ban.ignoreIP` should list the operator's own fixed IP / VPN range
to avoid self-lockout.

### 4.5 Kernel and sysctl hardening

`boot.kernel.sysctl` — **open submodule of attribute set of (sysctl option value)**,
default `{}`.

> *"Runtime parameters of the Linux kernel, as set by `sysctl(8)`. **Note that
> sysctl parameters names must be enclosed in quotes** (e.g. `"vm.swappiness"`
> instead of `vm.swappiness`). The value of each parameter may be a string, integer,
> boolean, or null (signifying the option will not appear at all)."*
> Example from the option: `{ "net.ipv4.tcp_syncookies" = false; "vm.swappiness" = 60; }`

The NixOS Wiki hardening page gives a **first-party, citable** baseline set
([NixOS Wiki, NixOS Hardening](https://wiki.nixos.org/wiki/NixOS_Hardening)):

```
boot.kernel.sysctl."kernel.kptr_restrict"              = "2";
boot.kernel.sysctl."net.core.bpf_jit_enable"            = false;
boot.kernel.sysctl."kernel.ftrace_enabled"               = false;
boot.kernel.sysctl."kernel.io_uring_disabled"            = 2;
boot.kernel.sysctl."net.ipv4.conf.all.log_martians"      = true;
boot.kernel.sysctl."net.ipv4.conf.all.rp_filter"         = "1";
boot.kernel.sysctl."net.ipv4.conf.default.log_martians"  = true;
boot.kernel.sysctl."net.ipv4.conf.default.rp_filter"     = "1";
boot.kernel.sysctl."net.ipv4.icmp_echo_ignore_broadcasts" = true;
boot.kernel.sysctl."net.ipv4.conf.all.accept_redirects"    = false;
boot.kernel.sysctl."net.ipv4.conf.all.secure_redirects"    = false;
boot.kernel.sysctl."net.ipv4.conf.default.accept_redirects" = false;
boot.kernel.sysctl."net.ipv4.conf.default.secure_redirects" = false;
boot.kernel.sysctl."net.ipv6.conf.all.accept_redirects"    = false;
boot.kernel.sysctl."net.ipv6.conf.default.accept_redirects" = false;
boot.kernel.sysctl."net.ipv4.conf.all.send_redirects"       = false;
```

**Which of the prompt's suggested sysctls exist:** `net.ipv4.ip_forward`,
`net.ipv4.conf.all.rp_filter`, `kernel.dmesg_restrict`, `kernel.kptr_restrict`,
`fs.protected_hardlinks`, `kernel.yama.ptrace_scope`, `net.ipv4.tcp_syncookies` are
**all real Linux sysctl names** and all are settable through `boot.kernel.sysctl`
(open submodule, so any sysctl name is accepted). But **only the ones on the Wiki
page have a first-party NixOS citation**; the rest are community convention (§10).

**Critical conflict — Docker forces IP forwarding.** nixpkgs' docker module sets:

```nix
boot.kernel.sysctl = {
  "net.ipv4.conf.all.forwarding"     = mkOverride 98 true;
  "net.ipv4.conf.default.forwarding" = mkOverride 98 true;
};
```
([docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix))

`mkOverride 98` is a high priority override, so **the operator cannot disable IPv4
forwarding while Docker is enabled**. Setting `net.ipv4.ip_forward = false` in
`boot.kernel.sysctl` will be silently overridden. This must be understood before
writing a hardening config — and it is why `networking.firewall.filterForward`
(nftables) matters.

**Kernel module lockdown.** `security.lockKernelModules` — *"Disable kernel module
loading once the system is fully initialised. Module loading is disabled until the
next reboot. Problems caused by delayed module loading can be fixed by adding the
module(s) in question to `boot.kernelModules`."* This is a **hard requirement** for
Docker: Docker loads `bridge`, `veth`, `br_netfilter` and `xt_nat` at module-load
time — nixpkgs adds them to `boot.kernelModules` for you, so lockdown is safe as
long as you do not add modules outside that list.

### 4.6 systemd service hardening — exact syntax

**Option type (verbatim from the index):**

> `systemd.services.<name>.serviceConfig`
> Type: **attribute set of (systemd option)**
> *"Each attribute in this set specifies an option in the `[Service]` section of the
> unit. See `systemd.service(5)` for details."*

So: `systemd.services.<name>.serviceConfig` is an attribute set whose **keys are
the CamelCase systemd `[Service]` directive names** and whose **values are the
directive values** (string, boolean, integer, or list — the `systemd option` type
accepts both scalar and list forms where systemd allows both).

Other verified `systemd.services.<name>` options:

| Option | Type | Notes |
| --- | --- | --- |
| `systemd.services.<name>.serviceConfig` | attribute set of (systemd option) | `[Service]` section |
| `systemd.services.<name>.unitConfig` | attribute set of (systemd option) | `[Unit]` section |
| `systemd.services.<name>.path` | list of (package or string) | *"Packages added to the service's PATH environment variable. Both the `bin` and `sbin` subdirectories of each package are added."* |
| `systemd.services.<name>.environment` | attribute set of (null or string or absolute path or package) | |
| `systemd.services.<name>.wantedBy` | list of string | *"creates a `.wants` symlink in the given target that exists statelessly without the need for running `systemctl enable`"* |
| `systemd.services.<name>.after` / `.before` / `.requires` / `.requisite` / `.wants` / `.bindsTo` / `.conflicts` / `.partOf` | list of string | Unit dependency types. |
| `systemd.services.<name>.script` | strings concatenated with `\n` | Main process. |
| `systemd.services.<name>.preStart` / `.postStart` / `.preStop` / `.postStop` / `.reload` | strings concatenated with `\n` | |
| `systemd.services.<name>.enable` | boolean | *"If set to false, this unit will be a symlink to `/dev/null`."* |
| `systemd.services.<name>.name` | string | |
| `systemd.services.<name>.startAt` | string or list of string | systemd.time(7) |
| `systemd.services.<name>.overrideStrategy` | `"asDropinIfExists"` \| `"asDropin"` | |
| `systemd.services.<name>.confinement.enable` | boolean | *"If set, all the required runtime store paths for this service are bind-mounted into a tmpfs-based `chroot(2)`."* |
| `systemd.services.<name>.confinement.mode` | `"full-apivfs"` \| `"chroot-only"` | *"In all cases, unless `serviceConfig.PrivateTmp=true` is set, both `/tmp` and `/var/tmp` paths are added to `InaccessiblePaths=`."* |
| `systemd.services.<name>.confinement.packages` | list of (string or package) | |
| `systemd.services.<name>.confinement.fullUnit` | boolean | |
| `systemd.services.<name>.enableStrictShellChecks` | boolean | Runs shellcheck on generated scripts; build fails on warnings. |
| `systemd.services.<name>.notSocketActivated` | boolean | |
| `systemd.services.<name>.restartIfChanged` / `.stopIfChanged` / `.reloadIfChanged` | boolean | |

**`systemd.user.services`** uses the same submodule type
(`utils.systemdUtils.types.services`), so `systemd.user.services.<name>.serviceConfig`
has the identical shape ([systemd/user.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/user.nix)).

**The directives themselves.** The NixOS Wiki's systemd hardening page
([NixOS Wiki, Systemd/Hardening](https://wiki.nixos.org/wiki/Systemd/Hardening))
gives a fully annotated, first-party NixOS example unit. Directives confirmed to
exist in `systemd.exec(5)` upstream (man7 reproduction,
[systemd.exec(5)](https://man7.org/linux/man-pages/man5/systemd.exec.5.html)):
`ProtectSystem=`, `ProtectHome=`, `PrivateTmp=`, `NoNewPrivileges=`,
`RestrictAddressFamilies=`, `CapabilityBoundingSet=`, `ReadWritePaths=`,
`ProtectKernelTunables=`, `ProtectKernelModules=`, `ProtectControlGroups=`,
`RestrictSUIDSGID=`, `LockPersonality=`, `SystemCallFilter=`, `PrivateDevices=`,
`PrivateUsers=`, `DevicePolicy=`, `MemoryDenyWriteExecute=`, `RestrictNamespaces=`,
`SystemCallArchitectures=`, `ProtectProc=`, `ProtectKernelLogs=`, `ProtectClock=`,
`ProtectHostname=`, `PrivateIPC=`, `PrivatePIDs=`, `PrivateMounts=`,
`RestrictRealtime=`, `RemoveIPC=`, `SocketBindDeny=`, `SocketBindAllow=`,
`SystemCallErrorNumber=`, `RootDirectory=`, `RuntimeDirectory=`, `StateDirectory=`,
`LogsDirectory=`, `BindPaths=`, `BindReadOnlyPaths=`, `UMask=`.

`IPAddressDeny=` / `IPAddressAllow=` are in **`systemd.resource-control(5)`**, not
`systemd.exec(5)` — confirmed present in
[systemd.resource-control(5)](https://man7.org/linux/man-pages/man5/systemd.resource-control.5.html)
alongside `CPUQuota=`, `MemoryMax=`, `TasksMax=`.

The Wiki also states the entry method: *"A good way to get started on a given
service is to look at the output of the command `systemd-analyze security myService`."*

**Do not** apply a blanket hardened `serviceConfig` to the Docker or Podman
services themselves — the Docker daemon needs broad host access by design.

### 4.7 SELinux / AppArmor status on NixOS

**Primary source:** [NixOS Wiki, Security](https://wiki.nixos.org/wiki/Security)
(page last edited 1 May 2026).

> **SELinux** — *"It is possible to use Security-Enhanced Linux (SELinux) in NixOS,
> but proper integration does not exist. This does not appear to have gotten much
> attention since 2019. However, there has been revived work in 2025 but there's no
> telling when things will land in NixOS."*

> **AppArmor** — *"As of April 2026, AppArmor is available for NixOS but also has
> not yet been properly integrated."* (links the AppArmor-on-NixOS roadmap discourse thread)

The `security.apparmor.enable` option's own text reinforces this:

> *"If you're enabling this module on a running system, note that a **reboot will
> be required** to activate AppArmor in the kernel. Also, beware that enabling this
> module **privileges stability over security** by not trying to kill unconfined but
> newly confinable running processes by default."*

**Conclusion:** AppArmor is available but immature. SELinux is not integrated. Do
not plan a hardening strategy around MAC; treat AppArmor as experimental and reboot
after enabling.

### 4.8 Other verified operational options

| Option | Type | Default | Note |
| --- | --- | --- | --- |
| `system.stateVersion` | string | `config.system.nixos.release` | §3.4 |
| `system.autoUpgrade.enable` | boolean | `false` | *"a systemd timer will run `nixos-rebuild switch --upgrade` once a day."* |
| `system.autoUpgrade.allowReboot` | boolean | `false` | *"Reboot the system into the new generation instead of a switch if the new generation uses a different kernel, kernel modules or initrd."* |
| `system.autoUpgrade.channel` | null or string | `null` | *"The URI of the NixOS channel to use for automatic upgrades."* |
| `system.activationScripts` | attribute set of (string or submodule) | `{}` | *"executed every time you boot the system or run `nixos-rebuild`, so it's important that they are idempotent and fast."* |
| `system.tools.nixos-rebuild.enableRun0Elevation` | boolean | `false` | Enables `polkit` + `polkit-stdin-agent` for `--elevate=run0`. |
| `environment.systemPackages` | list of package | `[]` | *"The set of packages that appear in `/run/current-system/sw`."* |
| `environment.memoryAllocator.provider` | `"libc"` \| `"graphene-hardened"` \| `"graphene-hardened-light"` \| `"jemalloc"` \| `"mimalloc"` \| `"scudo"` | `"libc"` | *"Selecting an alternative allocator (i.e., anything other than `libc`) may result in instability, data loss, and/or service failure."* |
| `services.logind.enable` | boolean | — | |
| `services.logind.settings.Login` | open submodule of (systemd option) | — | |
| `services.logind.settings.Login.KillUserProcesses` | boolean | **`false` in nixpkgs** | *"Defaulted to false in nixpkgs because many tools that rely on persistent user processes—like tmux, screen, mosh, VNC, nohup, and more—would break by the systemd-default behavior."* |
| `services.prometheus.enable` | boolean | `false` | *"Whether to enable Prometheus monitoring daemon."* |
| `services.prometheus.alertmanager.enable` | boolean | `false` | |
| `services.prometheus.alertmanager.port` | 16-bit uint | — | |
| `services.prometheus.alertmanager.openFirewall` | boolean | — | |
| `systemd.tmpfiles.rules` | list of string | `[]` | *"Rules for creation, deletion and cleaning of volatile and temporary files automatically. See `tmpfiles.d(5)`."* |
| `systemd.tmpfiles.settings` | attribute set of attribute set of attribute set of (submodule) | `{}` | |
| `systemd.tmpfiles.packages` | list of package | `[]` | Packages contributing `lib/tmpfiles.d` rules. |
| `systemd.network.networks` | attribute set of (submodule) | `{}` | |
| `systemd.network.networks.<name>.networkConfig` | attribute set of (systemd option) | `{}` | *"[Network] section of the unit. See `systemd.network(5)`."* |
| `systemd.network.networks.<name>.matchConfig` | attribute set of (systemd option) | `{}` | *"[Match] section."* |
| `systemd.network.links.<name>.matchConfig` / `.linkConfig` | attribute set of (systemd option) | `{}` | |
| `systemd.network.config.networkConfig` | attribute set of (systemd option) | `{}` | Global networkd config. |
| `networking.hostName` | string matching `^$\|^[[:alnum:]]([[:alnum:]_-]{0,61}[[:alnum:]])?$` | — | *"WARNING: Do not use underscores (`_`) or you may run into unexpected issues."* |
| `networking.domain` | null or string | `null` | *"The system domain name. Used to populate the `fqdn` value. The domain name is not configured for DNS resolution purposes."* |
| `networking.useDHCP` | boolean | `true` | |
| `networking.nftables.enable` | boolean | `false` | *"if you have Docker enabled you will not be able to use nftables without intervention."* |
| `networking.usePredictableInterfaceNames` | boolean | — | The Manual recommends keeping predictable names (`ens3`, `enp1s0`) and shows `systemd.network.links."10-wan".matchConfig.PermanentMACAddress` for stable naming. |

---

## 5. Docker on NixOS

### 5.1 `virtualisation.docker` — the verified option set

**Primary source:** `nixos/modules/virtualisation/docker.nix` on `nixos-unstable`
([source](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix)).

| Option | Type | Default | Notes |
| --- | --- | --- | --- |
| `virtualisation.docker.enable` | boolean | `false` | *"Users in the `docker` group can interact with the daemon (e.g. to start or stop containers) using the docker command line tool."* |
| `virtualisation.docker.daemon.settings` | **open submodule of (JSON value)** | `{}` | *"The attributes are serialized to JSON used as `daemon.conf`."* Freeform — any upstream `daemon.json` key is accepted. |
| `virtualisation.docker.daemon.settings.live-restore` | boolean | `versionOlder system.stateVersion "24.11"` | *"Allow `dockerd` to be restarted without affecting running container. This option is incompatible with docker swarm."* |
| `virtualisation.docker.liveRestore` | submodule | — | **Alias** of `daemon.settings.live-restore`. |
| `virtualisation.docker.storageDriver` | null \| `"aufs"` \| `"btrfs"` \| `"devicemapper"` \| `"overlay"` \| `"overlay2"` \| `"zfs"` | `null` | *"it is recommended to specify a storage driver explicitly, as docker's default varies over versions."* Warning: changing it makes existing containers/images inaccessible. |
| `virtualisation.docker.logDriver` | `"none"` \| `"json-file"` \| `"syslog"` \| `"journald"` \| `"gelf"` \| `"fluentd"` \| `"awslogs"` \| `"splunk"` \| `"etwlogs"` \| `"gcplogs"` \| `"local"` | `"journald"` | nixpkgs default differs from upstream's `json-file`. |
| `virtualisation.docker.extraOptions` | separated string | `""` | Extra `dockerd` command-line options. |
| `virtualisation.docker.listenOptions` | list of string | `["/run/docker.sock"]` | systemd.socket(5) `ListenStream` format. |
| `virtualisation.docker.enableOnBoot` | boolean | `true` | *"This is required for containers which are created with the `--restart=always` flag to work."* |
| `virtualisation.docker.package` | package | — | |
| `virtualisation.docker.extraPackages` | list of package | `[]` | Added to the daemon's PATH. |
| `virtualisation.docker.autoPrune.enable` | boolean | `false` | |
| `virtualisation.docker.autoPrune.flags` | list of string | `[]` | |
| `virtualisation.docker.autoPrune.dates` | string | `"weekly"` | systemd.time(7) |
| `virtualisation.docker.autoPrune.persistent` | boolean | `true` | |
| `virtualisation.docker.autoPrune.randomizedDelaySec` | string | `"0"` | ibid. |
| `virtualisation.docker.autoPrune.allVolumes.enable` | boolean | `false` | Requires `autoPrune.enable` (build assertion). |
| `virtualisation.docker.autoPrune.allVolumes.flags` | list of string | `[]` | |
| `virtualisation.docker.rootless.enable` | boolean | `false` | *"To interact with the daemon, one needs to set `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock`."* |
| `virtualisation.docker.rootless.daemon.settings` | JSON value | — | |
| `virtualisation.docker.rootless.setSocketVariable` | boolean | — | Points `DOCKER_HOST` at the rootless instance by default. |
| `virtualisation.docker.rootless.package` / `.extraPackages` | — | — | |
| `virtualisation.docker.enableNvidia` | boolean | `false` | **Deprecated** → `hardware.nvidia-container-toolkit.enable`. |
| `virtualisation.docker.extraOptions` | separated string | `""` | |

**Confirmed absent:** `openFirewall`, `portBindings`, `allowedRegistries`,
`allowedUsers`, `daemonSettings`, `prune`.

### 5.2 The Nix-specific Docker behaviours, straight from the module source

These are the facts that upstream Docker docs do **not** cover, and that the
research prompt asked about. All are from
[docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix):

1. **`--config-file` is already handled by nixpkgs — you do NOT need to set `ExecStart` yourself.**
   ```nix
   serviceConfig = {
     Type = "notify";
     ExecStart = [ "" ''
       ${cfg.package}/bin/dockerd \
         --config-file=${daemonSettingsFile} \
         ${cfg.extraOptions}
     '' ];
     ExecReload = [ "" "${pkgs.procps}/bin/kill -s HUP $MAINPID" ];
   };
   ```
   `daemonSettingsFile` is `pkgs.formats.json { }.generate "daemon.json" cfg.daemon.settings`
   — a **read-only Nix store path**. The prompt's premise ("`ExecStart` needing
   `--config-file` because the Nix-managed daemon.json is read-only in the store")
   is **correct as a rationale but wrong as a requirement**: nixpkgs already does it.
   Overriding `ExecStart` would *break* the daemon.json wiring.

2. **The socket is created by a systemd socket unit, not by the daemon:**
   ```nix
   systemd.sockets.docker = {
     description = "Docker Socket for the API";
     wantedBy = [ "sockets.target" ];
     socketConfig = {
       ListenStream = cfg.listenOptions;   # default [ "/run/docker.sock" ]
       SocketMode  = "0660";
       SocketUser  = "root";
       SocketGroup = "docker";
     };
   };
   ```
   The `docker` group therefore holds **0660 access to the root-owned docker socket**.

3. **Service ordering is already handled:**
   ```nix
   systemd.services.docker = {
     wantedBy = optional cfg.enableOnBoot "multi-user.target";
     after    = [ "network.target" "docker.socket" ];
     requires = [ "docker.socket" ];
     ...
   };
   ```
   Note: `network.target`, **not** `network-online.target`. If the container needs
   the network at boot (e.g. pulling an image), order matters — this is a known
   failure mode on DHCP-only VPSes.

4. **`virtualisation.docker.enable` also forces IP forwarding** (see §4.5) and loads
   `bridge`, `veth`, `br_netfilter`, `xt_nat` kernel modules.

5. **The daemon's `daemon.json` is pre-seeded by nixpkgs** with:
   ```nix
   virtualisation.docker.daemon.settings = {
     group = "docker";
     hosts = [ "fd://" ];
     log-driver = mkDefault cfg.logDriver;
     storage-driver = mkIf (cfg.storageDriver != null) (mkDefault cfg.storageDriver);
     runtimes = mkIf cfg.enableNvidia { ... };
   };
   ```
   `hosts = [ "fd://" ]` means systemd socket activation. **Do not override `hosts`** —
   upstream warns: *"On systems that use systemd to start the Docker daemon, `-H` is
   already set, so you can't use the `hosts` key in `daemon.json` to add listening
   addresses"* ([dockerd reference](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file)).

6. **`nixpkgs` does not open any firewall ports for Docker.** There is no
   `openFirewall` option.

### 5.3 `virtualisation.oci-containers` and the docker/podman interaction

**Primary source:** [oci-containers.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/oci-containers.nix)
and [podman/default.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/podman/default.nix).

| Option | Type | Default |
| --- | --- | --- |
| `virtualisation.oci-containers.backend` | `"podman"` \| `"docker"` | `"podman"` |
| `virtualisation.oci-containers.containers` | attribute set of (submodule) | `{}` |
| `virtualisation.oci-containers.containers.<name>.image` | string | — |
| `virtualisation.oci-containers.containers.<name>.ports` | list of string | `[]` |
| `virtualisation.oci-containers.containers.<name>.volumes` | list of string | `[]` |
| `virtualisation.oci-containers.containers.<name>.autoStart` | boolean | — |
| `virtualisation.oci-containers.containers.<name>.environment` | attribute set of string | `{}` |
| `virtualisation.oci-containers.containers.<name>.extraOptions` | list of string | `[]` |
| `virtualisation.oci-containers.containers.<name>.preRunExtraOptions` | list of string | `[]` |
| `virtualisation.oci-containers.containers.<name>.user` | null or string | `null` |
| `virtualisation.oci-containers.containers.<name>.privileged` | boolean | `false` |
| `virtualisation.oci-containers.containers.<name>.capabilities` | lazy attribute set of (null or boolean) | `{}` |
| `virtualisation.oci-containers.containers.<name>.pull` | `"always"` \| `"missing"` \| `"never"` \| `"newer"` | — |
| `virtualisation.oci-containers.containers.<name>.serviceName` | string | `"<backend>-<name>"` |
| `virtualisation.oci-containers.containers.<name>.dependsOn` | list of string | `[]` |
| `virtualisation.oci-containers.containers.<name>.hostname` | null or string | `null` |
| `virtualisation.oci-containers.containers.<name>.cmd` | list of string | `[]` |
| `virtualisation.oci-containers.containers.<name>.entrypoint` | null or string | `null` |
| `virtualisation.oci-containers.containers.<name>.workdir` | null or string | `null` |
| `virtualisation.oci-containers.containers.<name>.log-driver` | string | `"journald"` |
| `virtualisation.oci-containers.containers.<name>.labels` | attribute set of string | `{}` |
| `virtualisation.oci-containers.containers.<name>.imageFile` | null or path in the Nix store | `null` |
| `virtualisation.oci-containers.containers.<name>.imageStream` | null or package | `null` |
| `virtualisation.oci-containers.containers.<name>.podman.user` | string | — |
| `virtualisation.oci-containers.containers.<name>.podman.sdnotify` | `"conmon"` \| `"healthy"` \| `"container"` | — |
| `virtualisation.podman.enable` | boolean | `false` |
| `virtualisation.podman.dockerSocket.enable` | boolean | `false` |
| `virtualisation.podman.dockerCompat` | boolean | `false` |

**The socket-conflict question — verified answer:**

The prompt asks whether `virtualisation.docker` and `virtualisation.oci-containers`
(podman) *"conflict on the `docker.socket`/`podman.socket` units."* The accurate
answer is **more nuanced**:

* The two engines create **different** systemd socket units: `docker.socket`
  (`SocketGroup = "docker"`) and `podman.socket` (`SocketGroup = "podman"`).
  Enabling both does **not** produce a unit-name collision.
* The **real, asserted** conflicts are in the podman module:
  ```nix
  assertions = [
    { assertion = cfg.dockerCompat      -> !config.virtualisation.docker.enable;
      message  = "Option dockerCompat conflicts with docker"; }
    { assertion = cfg.dockerSocket.enable -> !config.virtualisation.docker.enable;
      message  = "The options virtualisation.podman.dockerSocket.enable and
                   virtualisation.docker.enable conflict, because only one can
                   serve the socket."; }
  ];
  ```
  So: **do not** enable `virtualisation.podman.dockerSocket.enable` or
  `virtualisation.podman.dockerCompat` alongside `virtualisation.docker.enable`.
  `virtualisation.podman.enable` alone *can* coexist with Docker.
* `virtualisation.oci-containers.backend` selects which runtime the declarative
  containers use. With the `docker` backend, the generated unit gets
  `after = [ "docker.service" "docker.socket" ]` and
  `path = [ config.virtualisation.docker.package ]`; with `podman`,
  `path = [ config.virtualisation.podman.package ]`.
* `virtualisation.oci-containers.containers.<name>.ports` **bypasses the NixOS
  firewall** (quoted verbatim in §4.3).
* `virtualisation.oci-containers.containers.<name>.volumes` is *"a list of `src:dst`
  strings to allow for `src` to refer to `/nix/store` paths"*.

### 5.4 Docker Engine official hardening — real `daemon.json` keys

**Primary source:** [dockerd reference, "Daemon configuration file"](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file).
All keys below appear in the official "full example of the allowed configuration
options on Linux" and in the `dockerd` flag list.

| `daemon.json` key | Flag equivalent | What the official docs say |
| --- | --- | --- |
| `icc` | `--icc` (default `true`) | *"Enable inter-container communication for the default bridge network."* Setting `false` disables container-to-container traffic on the default bridge. |
| `no-new-privileges` | `--no-new-privileges` | *"Set `no-new-privileges` by default for new containers."* |
| `userns-remap` | `--userns-remap string` | *"User/Group setting for user namespaces."* Maps container root to a non-uid-0 host user. Official security page: *"This feature allows for the root user in a container to be mapped to a non uid-0 user outside the container, which can help to mitigate the risks of container breakout. This facility is available but not enabled by default."* |
| `live-restore` | `--live-restore` | *"Enable live restore of docker when containers are still running."* |
| `userland-proxy` | `--userland-proxy` (default `true`) | *"Use userland proxy for loopback traffic."* |
| `default-address-pools` | `--default-address-pool` | *"Default address pools for node specific local networks."* Shape: list of `{ base, size }`. |
| `authorization-plugins` | `--authorization-plugin list` | *"Authorization plugins to load."* The security page notes plugins *"offer more fine-grained control to supplement authentication from mutual TLS."* |
| `exec-opts` | `--exec-opt list` | *"Runtime execution options."* |
| `default-ulimits` | `--default-ulimit` | *"Default ulimits for containers."* Shape: `{ "<name>": { "Name": ..., "Soft": ..., "Hard": ... } }`. |
| `storage-driver` | `--storage-driver string` | Storage driver selection. |
| `storage-opts` | `--storage-opt list` | |
| `log-driver` | `--log-driver string` (default `json-file`) | Default logging driver. |
| `log-opts` | `--log-opt map` | Logging-driver options, e.g. `max-size`, `max-file` for `json-file`. The logging-driver page documents rotation via `max-size`/`max-file`. |
| `hosts` | `-H, --host list` | Daemon listen addresses. **Do not set in nixpkgs** (already `fd://`). |
| `group` | `-G, --group string` (default `docker`) | Group for the unix socket. |
| `iptables` / `ip6tables` | `--iptables` / `--ip6tables` (default `true`) | Enable iptables rule creation. |
| `ip-forward` | `--ip-forward` (default `true`) | *"Enable IP forwarding in system configuration."* |
| `ip-masq` | `--ip-masq` (default `true`) | Enable IP masquerading. |
| `fixed-cidr` / `fixed-cidr-v6` / `bip` / `bip6` | | Default bridge subnetting. |
| `seccomp-profile` | `--seccomp-profile string` (default `builtin`) | *"Set to `unconfined` to disable the default seccomp profile."* |
| `apparmor-profile` | `--apparmor-profile string` | |
| `selinux-enabled` | `--selinux-enabled` | |
| `default-cgroupns-mode` | `--default-cgroupns-mode string` (default `private`) | |
| `default-runtime` | `--default-runtime string` (default `runc`) | |
| `tls` / `tlsverify` / `tlscacert` / `tlscert` / `tlskey` | | mTLS for remote daemon access. |

**Critical constraint from the official docs:** *"The options set in the
configuration file must not conflict with options set using flags. The Docker daemon
fails to start if an option is duplicated between the file and the flags, regardless
of their value."* — So a NixOS `daemon.settings` key that duplicates a flag nixpkgs
passes on the command line will prevent the daemon from starting. nixpkgs passes
only `--config-file=<store path>` plus `cfg.extraOptions`, so the conflict surface
is `cfg.extraOptions` vs `daemon.settings`.

### 5.5 Docker socket exposure — the root-equivalent risk

**Primary source:** [Docker Engine security, "Docker daemon attack surface"](https://docs.docker.com/engine/security/)
and [Linux post-installation steps](https://docs.docker.com/engine/install/linux-postinstall/).

Verbatim from the security page:

> *"First of all, only trusted users should be allowed to control your Docker
> daemon. This is a direct consequence of some powerful Docker features.
> Specifically, Docker allows you to share a directory between the Docker host and a
> guest container; and it allows you to do so without limiting the access rights of
> the container. This means that you can start a container where the `/host`
> directory is the `/` directory on your host; and the container can alter your host
> filesystem without any restriction."*

Verbatim from the post-install page:

> *"**The `docker` group grants root-level privileges to the user.** For details on
> how this impacts security in your system, see Docker Daemon Attack Surface."*

And on the shared-secret approach:

> *"Permanent membership in the `docker` group gives every process in your login
> session access to the Docker socket. […] A shared group credential reduces
> ambient access to the Docker socket, but it doesn't reduce the root-level
> privileges granted after access is authorized. Group credentials are also shared
> secrets and don't provide per-user accountability. **This method isn't a
> security boundary against malicious code running as your user.**"*

**NixOS-specific manifestation:** nixpkgs' docker module creates
`users.groups.docker` and sets the socket's `SocketGroup = "docker"` with
`SocketMode = "0660"`. Any user in `users.users.<name>.extraGroups` containing
`"docker"` is therefore root-equivalent. The nixpkgs option text itself flags
this: *"Users in the `docker` group can interact with the daemon."*

**Recommendation:** put **only** the specific operator account in `docker`, and
prefer `virtualisation.docker.rootless.enable = true` where the workload allows
it. Note the Portainer docs' caveat: *"Docker is running as root. Portainer with
rootless Docker has some limitations, and requires additional configuration."*

---

## 6. Portainer on NixOS

### 6.1 What Portainer officially supports on Linux

**Primary source:** [docs.portainer.io/llms.txt](https://docs.portainer.io/llms.txt)
(the official documentation index) and the install pages.

The **complete** set of documented Portainer CE Linux install methods in the
official docs is:

| Method | Official page |
| --- | --- |
| Docker Standalone | [start/install-ce/server/docker/linux.md](https://docs.portainer.io/start/install-ce/server/docker/linux.md) |
| Docker Swarm | [start/install-ce/server/swarm/linux.md](https://docs.portainer.io/start/install-ce/server/swarm/linux.md) |
| Podman | [start/install-ce/server/podman/linux.md](https://docs.portainer.io/start/install-ce/server/podman/linux.md) |
| Kubernetes | [start/install-ce/server/kubernetes.md](https://docs.portainer.io/start/install-ce/server/kubernetes.md) |

**There is no documented "binary / systemd" install page in the current official
Portainer documentation.** The `llms.txt` index contains no `binary` or `systemd`
install entry. This is a material finding: the request's option (b) — "install the
Portainer binary via `systemd.services.portainer`" — is **not** an officially
documented Portainer install method.

**However**, the official upstream repo *does* ship a systemd unit and a package
spec, which makes option (b) technically feasible and citable:

* [`distribution/portainer.service`](https://github.com/portainer/portainer/blob/develop/distribution/portainer.service):
  ```ini
  [Unit]
  Description=Portainer.io management ui
  After=docker.service
  Wants=docker.service
  Wants=docker-latest.service

  [Service]
  Type=simple
  Restart=always
  RestartSec=3
  Environment=ASSETS=/usr/share/portainer
  Environment=DBFILES=/var/lib/portainer
  EnvironmentFile=-/etc/sysconfig/%p
  ExecStart=/usr/sbin/portainer -a $ASSETS -d $DBFILES

  [Install]
  WantedBy=multi-user.target
  ```
* [`distribution/portainer.spec`](https://github.com/portainer/portainer/blob/develop/distribution/portainer.spec)
  — the RPM spec shows the canonical on-disk layout: binary at `/usr/sbin/portainer`,
  web assets at `/usr/share/portainer/public`, database at `/var/lib/portainer`.

**There is no `portainer` package in nixpkgs** — the only matches for "portainer"
in the nixpkgs package index are the Python clients `python313Packages.pyportainer`
and `python314Packages.pyportainer`. A Nix-native binary install therefore requires
`pkgs.fetchurl` of the official tarball.

### 6.2 Official release artifacts and checksum pinning

**Primary source:** [GitHub Releases API, `portainer/portainer`](https://api.github.com/repos/portainer/portainer/releases/latest)
and the release page [2.45.3 LTS](https://github.com/portainer/portainer/releases/tag/2.45.3).

Latest release at time of research: **tag `2.45.3`**, published `2026-10-21`.

Linux assets (each with a matching checksum file):

```
portainer-2.45.3-linux-amd64.tar.gz
portainer-2.45.3-linux-amd64-checksum.txt
portainer-2.45.3-linux-arm.tar.gz
portainer-2.45.3-linux-arm-checksum.txt
portainer-2.45.3-linux-arm64.tar.gz
portainer-2.45.3-linux-arm64-checksum.txt
portainer-2.45.3-linux-ppc64le.tar.gz
portainer-2.45.3-linux-ppc64le-checksum.txt
```

Official checksum file content for linux-amd64:

```
SHA256 (portainer-2.45.3-linux-amd64.tar.gz) = ab4ed7d58855f37d94c58d0a4316da5a1c13348269268a64486664a04de3b6a1
```

**Tarball structure** (verified by download):

```
portainer/portainer                 <- the server binary
portainer/public/                   <- the web UI static assets
portainer/mustache-templates/
```

This exactly matches the RPM spec's layout, and gives a deterministic Nix
derivation: `pkgs.fetchurl` with the SHA256 above, then a `postInstall` that puts
`portainer` on `PATH` and `public/` into a `share` output. The official checksum
file gives the **authoritative SHA256** to pin.

### 6.3 Portainer's own documented requirements and ports

**Primary source:** [start/requirements-and-prerequisites.md](https://docs.portainer.io/start/requirements-and-prerequisites.md).

> *"On the Portainer Server the following ports must be open:*
> - *TCP port `9443` (or `30779` for Kubernetes with NodePort) for the UI and API*
> - *TCP port `8000` (or `30776` for Kubernetes with NodePort) for the TCP tunnel
>   server for Edge Agents. This port is optional and only required if using Edge
>   Compute features with Edge Agents.*
>
> *For the Portainer Agent:*
> - *TCP port `9001` (or `30778` for Kubernetes with NodePort) must be accessible on
>   the Agent from the Portainer Server instance.*
>
> *The Portainer Edge Agent does not require any open ports."*

And: *"The Portainer Server requires persistent storage in order to maintain the
database and configuration information it needs to function."*

**The documented Docker install command** (Docker page):

```bash
docker volume create portainer_data
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data portainer/portainer-ce:lts
```

And the official compose file (`https://downloads.portainer.io/ce-sts/portainer-compose.yaml`):

```yaml
services:
  portainer:
    container_name: portainer
    image: portainer/portainer-ce:lts
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    ports:
      - 9443:9443
      - 8000:8000  # Remove if you do not intend to use Edge Agents
volumes:
  portainer_data:
    name: portainer_data
networks:
  default:
    name: portainer_network
```

**The Podman install command** (Podman page) — note `--privileged`:

```
podman run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
  --privileged \
  -v /run/podman/podman.sock:/var/run/docker.sock \
  -v portainer_data:/data portainer/portainer-ce:lts
```

And the Podman page's own limitation: *"Portainer manages Podman through Podman's
Docker-compatible API — the compatibility layer Podman's own service exposes to
emulate the Docker Engine API — **not a native Podman integration**. Podman
environments therefore behave like Docker environments in Portainer, and support is
limited to configurations where that Docker-compatible API behaves consistently."*

**Supported-configuration matrix** (from the requirements page, CE):

| Portainer CE version | Docker | Kubernetes | Podman | Architectures |
| --- | --- | --- | --- | --- |
| 2.45.3 LTS (2026-10-22) | 28.5.1, 29.8.1 | 1.34, 1.35, 1.36 | 5.8.5 | ARM64, x86_64 |
| 2.39.6 LTS (2026-08-13) | 28.5.1, 29.7.1 | 1.34, 1.35, 1.36 | 5.7.1 | ARM64, x86_64 |

Portainer also documents the Podman platform constraint: *"CentOS 9 with the latest
version of Podman 5.x installed and working on your Podman host. Other Podman
versions and Linux distros may work but we currently only support the above."*

### 6.4 Portainer's documented security guidance

**Primary source:** [faqs/installing/setup-token.md](https://docs.portainer.io/faqs/installing/setup-token.md),
[advanced/ssl.md](https://docs.portainer.io/advanced/ssl.md),
[admin/settings.md](https://docs.portainer.io/admin/settings.md).

* **TLS on 9443 is on by default.** *"By default, Portainer generates and uses a
  self-signed SSL certificate to secure port `9443`. Alternatively you can provide
  your own SSL certificate during installation or via the Portainer UI after
  installation is complete."*
* **Setup token (new, ≥ 2.43 / 2.39.4).** *"new Portainer instances require a setup
  token to complete first-time setup. This token exists to protect a freshly
  started instance from being claimed by someone other than the intended
  administrator."* The token is retrieved from the container logs
  (`docker logs <container>` / `podman logs <container>`), is one-time use, and
  *"the user must be created within 5 minutes"*.
* **Programmatic administrator credentials.** Portainer also accepts the
  administrator's credentials as command-line flags, *"pre-set the administrator
  at startup. No token is generated or required. This is the recommended approach
  for managed or marketplace installs where you may not have direct access to the
  server logs."* This configuration does not use them: the credentials would then
  live in the systemd unit file, which is world-readable.
* **Skipping the token.** `--no-setup-token` *"disables the token requirement
  entirely. Only use this when the instance runs on a network you fully control and
  trust, such as an isolated private or air-gapped network."*
* **Port 9000 (legacy).** *"If you require HTTP port `9000` open for legacy reasons,
  add the following to your `docker run` command: `-p 9000:9000`."* — i.e. Portainer
  itself frames 9000 as **legacy**; it is not required.
* **Agent security.** The Agent listens for an incoming claim from a Portainer
  instance; a claimed Agent *"will allow only the Portainer instance that claimed
  it to manage it"*, and the Agent shuts down if unclaimed within 5 minutes. The
  optional `AGENT_SECRET` env var allows any Portainer instance with the matching
  secret to manage the Agent.
* The **Edge Agent** uses mTLS with a CA installed in Portainer plus a rotating key.

**On the Agent port 9000 warning specifically:** the official docs do **not**
contain a dedicated security warning about exposing agent port 9000. What they do
say is that the **Agent** port is **9001**, that the **Edge Agent requires no open
ports**, and that 9000 is the *legacy HTTP UI* port. The recommended
configuration is therefore: expose **9443** (TLS UI/API) and, only if using Edge
Agents, **8000** (TCP tunnel). Do not expose 9000. **8000 is a raw TCP tunnel for
Edge Agents** and should be bound to a trusted network.

---

## 7. Docker + Portainer Integration — mechanism options and trade-offs

| | **(a) Podman via `virtualisation.oci-containers`** | **(b) Native binary via `systemd.services.portainer`** | **(c) Docker via `docker run` wrapper** |
| --- | --- | --- | --- |
| **Shape** | `virtualisation.podman.enable = true;` + `virtualisation.oci-containers.backend = "podman"` + `virtualisation.oci-containers.containers.portainer = { image = "docker.io/portainer/portainer-ce:<version>"; ... }` | `pkgs.fetchurl` the official tarball (SHA256 pinned from the official `-checksum.txt`), install binary + `public/` assets, then `systemd.services.portainer = { serviceConfig = { ... }; wantedBy = [ "multi-user.target" ]; }` | `virtualisation.docker.enable = true` + a `systemd.services.portainer` whose `script` runs `docker run … portainer/portainer-ce:<version>` |
| **Official support status** | Officially documented (Podman page) — but Portainer says Podman support is *"limited to configurations where that Docker-compatible API behaves consistently"*, and the Podman command requires **`--privileged`** | **Not documented** by Portainer, but the upstream repo ships `distribution/portainer.service` and `distribution/portainer.spec`, so the layout is authoritative | Officially documented (Docker page) — the canonical install |
| **Port mapping** | `containers.portainer.ports = [ "9443:9443" ]` — but **"Publishing a port bypasses the NixOS firewall"** | Direct: the binary listens on 9443 itself; the NixOS firewall applies normally | Must be expressed in the `docker run` command — **`virtualisation.docker` has no `portBindings` option**, so it lives in the wrapper script, and Docker's DNAT bypasses the NixOS firewall |
| **Socket** | `/run/podman/podman.sock:/var/run/docker.sock` (note: `podman.sock`, not `docker.sock`) | N/A for the Portainer process itself; the Agent mode needs the socket | `/run/docker.sock:/var/run/docker.sock` (the NixOS path is `/run/docker.sock`; `/var/run` is a symlink to `/run`) |
| **Persistence** | Podman volume `portainer_data` mounted at `/data` | `/var/lib/portainer` (the `-d $DBFILES` path from the official unit) | Docker volume `portainer_data` mounted at `/data` |
| **Version pinning** | `image = "docker.io/portainer/portainer-ce:2.45.3"` — the tag is pinned, but the **image digest is not**, unless you pin by digest | Exact: `fetchurl` with the official SHA256 → fully deterministic | Same as (a): tag-pinned, digest unpinned unless pinned explicitly |
| **Pros** | Fully declarative; systemd unit generated; `oci-containers` supports `dependsOn`, `volumes`, `environment`, `extraOptions`, `capabilities`, `pull` policy | Deterministic build; no container runtime at all; smallest privilege surface; official systemd unit as reference | Matches Portainer's documented, tested install exactly; simplest to reason about; `docker.sock` is the documented path |
| **Cons** | Podman support is explicitly "limited"; requires `--privileged` (Podman page) which is a **large** privilege grant; NixOS `security.apparmor` is not integrated so MAC does not compensate | **Not a documented Portainer install method**; the Portainer binary needs the `public/` assets at a fixed relative path, and the operator must supply the systemd unit; Portainer's own unit assumes `/usr/sbin/portainer` and `/usr/share/portainer` paths that NixOS must adapt | The `docker run` command must live in a systemd `script`; container lifecycle is managed by Docker, not systemd; port publishing bypasses the NixOS firewall; `docker.sock` mount gives Portainer root-equivalent access to the host |
| **Portainer's own view of the socket** | The Docker install page explicitly requires the socket mount — Portainer is *designed* to have it | Portainer in binary mode would need a different way to reach Docker (none documented) | Same as (a) |

### 7.1 Recommendation

**Option (c) — Docker + a `docker run` wrapper — is the recommendation**, because:

1. It is the **only** Docker-based path Portainer officially documents and tests for
   Linux, with a published compatibility matrix (Docker 28.5.1 / 29.8.1 for CE
   2.45.3).
2. It matches Portainer's documented persistent-volume convention
   (`portainer_data` → `/data`) and the documented `portainer_data` compose volume.
3. It keeps the container's identity, restart policy, and `docker.sock` mount
   exactly as Portainer documents.

But note the two consequences and design around them:

* **Because `virtualisation.docker` has no `portBindings` option**, the
  `-p 9443:9443` mapping must live inside the `docker run` command in a
  `systemd.services.<name>.script` (or a `preStart`). This means the port mapping
  is **not** declarative in the NixOS option sense — it is a string in a script.
* **Because published ports bypass the NixOS firewall**, the NixOS firewall will
  **not** protect 9443. The mitigation is to publish to loopback and front
  Portainer with a reverse proxy (which is the standard deployment shape anyway),
  or to publish to the public interface and accept that the NixOS firewall does
  not gate it.

If you want the *firewall to actually gate* Portainer, option (b) (native binary)
is the only one of the three where the NixOS firewall applies to the Portainer
listener — at the cost of being an undocumented install method.

### 7.2 Docker daemon hardening on a NixOS host

If Docker is enabled, the following `daemon.json` keys are the ones with real
upstream meaning and that are compatible with nixpkgs' pre-seeded
`daemon.settings` (which already sets `group`, `hosts`, `log-driver`,
`storage-driver`):

| Key | NixOS expression shape | Note |
| --- | --- | --- |
| `icc` | `false` | Disables inter-container communication on the default bridge. |
| `no-new-privileges` | `true` | `no-new-privileges` by default for new containers. |
| `userns-remap` | `"<uid>:<gid>"` | Mitigates container-breakout risk. **Must be decided before any image is pulled** — remapping changes the ownership of everything in `/var/lib/docker`. |
| `live-restore` | `true` | Survives daemon restarts. **Incompatible with Docker Swarm.** Note nixpkgs' default depends on `system.stateVersion < "24.11"`. |
| `log-opts` | e.g. `{ "max-size" = "10m"; "max-file" = "3"; }` | Rotates `json-file` logs; prevents disk exhaustion. Upstream: *"Over time, these log files expand in size, leading to potential exhaustion of disk resources."* |
| `default-ulimits` | `{ nofile = { Name = "nofile"; Soft = 64000; Hard = 64000; }; }` | |
| `authorization-plugins` | list of plugin names | Fine-grained authorisation on top of socket permissions. |
| `default-address-pools` | list of `{ base; size; }` | Predictable container subnets. |

**Do NOT set `hosts`** — nixpkgs sets `hosts = [ "fd://" ]` and upstream warns the
daemon will fail if `hosts` is also given as a flag.

**Do NOT override `storage-driver` casually** — nixpkgs warns *"Changing the storage
driver will cause any existing containers and images to become inaccessible."*

---

## 8. Verified Option Reference

Every option below was resolved against the **live official option index for
`nixos-unstable`** (and, where noted, confirmed in the nixpkgs module source).
Options marked **freeform** are not individually declared but are accepted because
their parent submodule has a `freeformType`.

**Option URL convention:** `https://search.nixos.org/options?channel=unstable&query=<option>`.
For submodule parents, use the parent path.

### 8.1 Boot, storage and kernel

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `boot.kernel.sysctl` | open submodule of attribute set of (sysctl option value) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=boot.kernel.sysctl) |
| `boot.kernel.sysctl."net.core.rmem_max"` | null or unsigned integer | `null` | ibid. |
| `boot.kernel.sysctl."net.core.wmem_max"` | null or unsigned integer | `null` | ibid. |
| `boot.kernelParams` | list of string | `[]` | [options](https://search.nixos.org/options?channel=unstable&query=boot.kernelParams) |
| `boot.kernelPatches` | list of (attribute set) | `[]` | [options](https://search.nixos.org/options?channel=unstable&query=boot.kernelPatches) |
| `boot.kernelModules` | (attribute set of boolean) or (list of string) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=boot.kernelModules) |
| `boot.blacklistedKernelModules` | (attribute set of boolean) or (list of string) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=boot.blacklistedKernelModules) |
| `boot.initrd.systemd` | submodule (no `enable` — **removed**) | — | [initrd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/initrd.nix) |
| `boot.initrd.systemd.network.enable` | boolean | — | ibid. |
| `boot.initrd.systemd.network.wait-online.enable` | boolean | — | ibid. |
| `boot.initrd.systemd.network.wait-online.timeout` | unsigned integer | — | ibid. |
| `boot.initrd.systemd.fido2.enable` | boolean | — | ibid. |
| `boot.initrd.systemd.dbus.enable` | boolean | — | ibid. |
| `boot.initrd.systemd.shell.enable` | boolean | `config.environment.shell.enable` | ibid. — marked `internal = true`, so it is **not listed in the option index** but is still settable; *"this option actually strictly disables all shells in the initrd"* |
| `boot.loader.grub.enable` | boolean | `!config.boot.isContainer` | [options](https://search.nixos.org/options?channel=unstable&query=boot.loader.grub.enable) |
| `boot.loader.grub.devices` | list of string | `[]` | ibid. |
| `boot.loader.systemd-boot.enable` | boolean | `false` | [options](https://search.nixos.org/options?channel=unstable&query=boot.loader.systemd-boot.enable) |
| `boot.zfs.enabled` | boolean | — | [options](https://search.nixos.org/options?channel=unstable&query=boot.zfs.enabled) |
| `boot.zfs.package` | package | — | ibid. |
| `boot.zfs.requestEncryptionCredentials` | boolean or list of string | — | ibid. |
| `boot.zfs.forceImportRoot` | boolean | — | ibid. |
| `boot.zfs.forceImportAll` | boolean | — | ibid. |
| `boot.zfs.tzpfms.enable` | boolean | — | ibid. |
| `boot.zfs.extraPools` | list of string | — | ibid. |
| `fileSystems` | attribute set of (submodule) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=fileSystems) |
| `swapDevices` | list of (submodule) | `[]` | [options](https://search.nixos.org/options?channel=unstable&query=swapDevices) |
| `zramSwap.enable` | boolean | — | [options](https://search.nixos.org/options?channel=unstable&query=zramSwap.enable) |
| `zramSwap.algorithm` | one of `"842"`/`"lzo"`/`"lzo-rle"`/`"lz4"`/`"lz4hc"`/`"zstd"` or string | — | ibid. |
| `zramSwap.memoryPercent` | positive integer | `1/2` of RAM | ibid. |
| `zramSwap.memoryMax` | null or signed integer | `null` | ibid. |
| `zramSwap.swapDevices` | signed integer | `1` | ibid. |
| `zramSwap.priority` | signed integer | — | ibid. |

### 8.2 Users, SSH, PAM, sudo

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `users.users` | attribute set of (submodule) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=users.users) |
| `users.users.<name>.description` | string | — | [users-groups.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/users-groups.nix) |
| `users.users.<name>.uid` / `.gid` | signed integer | — | ibid. |
| `users.users.<name>.isNormalUser` | boolean | — | ibid. |
| `users.users.<name>.group` / `.extraGroups` | string / list of string | — | ibid. |
| `users.users.<name>.home` / `.shell` | string / string | — | ibid. |
| `users.users.<name>.createHome` | boolean | — | ibid. |
| `users.users.<name>.openssh.authorizedKeys.keys` | list of string | `[]` | [sshd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ssh/sshd.nix) |
| `users.users.<name>.openssh.authorizedKeys.keyFiles` | list of path | `[]` | ibid. |
| `users.users.<name>.openssh.authorizedPrincipals` | list of string | `[]` | ibid. |
| `users.groups` | attribute set of (submodule) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=users.groups) |
| `users.mutableUsers` | boolean | **`true`** | [options](https://search.nixos.org/options?channel=unstable&query=users.mutableUsers) |
| `services.openssh.enable` | boolean | `false` | [options](https://search.nixos.org/options?channel=unstable&query=services.openssh.enable) |
| `services.openssh.ports` | list of 16-bit uint | `[22]` | ibid. |
| `services.openssh.openFirewall` | boolean | `true` | ibid. |
| `services.openssh.settings` | open submodule (freeform) of attribute set of (atom) | `{}` | [sshd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ssh/sshd.nix) |
| `services.openssh.settings.PermitRootLogin` | null or one of the values sshd accepts for the directive | **the strict one** (key-only root login) | ibid. |
| `services.openssh.settings.X11Forwarding` | null or boolean | **`false`** | ibid. |
| `services.openssh.settings.LogLevel` | null or one of `QUIET`…`DEBUG3` | `null` | ibid. |
| `services.openssh.settings.UsePAM` | null or boolean | `null` | ibid. |
| `services.openssh.settings.KbdInteractiveAuthentication` | null or boolean | `null` | ibid. |
| `services.openssh.settings.AllowUsers` / `.DenyUsers` / `.AllowGroups` / `.DenyGroups` | null or list of string | `null` | ibid. |
| `services.openssh.settings.Ciphers` / `.KexAlgorithms` / `.Macs` | null or list of string | curated set | ibid. |
| `services.openssh.settings.AcceptEnv` | null or list of string | `null` | ibid. |
| `services.openssh.settings.Banner` | null or absolute path | `null` | ibid. |
| `services.openssh.settings.AuthorizedPrincipalsFile` | null or string | `"none"` | ibid. |
| `services.openssh.settings.GatewayPorts` | null or string | `null` | ibid. |
| `services.openssh.settings.StrictModes` | null or boolean | `null` | ibid. |
| `services.openssh.settings.UseDns` | null or boolean | `null` | ibid. |
| `services.openssh.settings.PrintMotd` | null or boolean | `null` | ibid. |
| `services.openssh.settings.ModuliFile` | absolute path | — | ibid. |
| `services.openssh.enableRecommendedAlgorithms` | boolean | `true` | [options](https://search.nixos.org/options?channel=unstable&query=services.openssh.enableRecommendedAlgorithms) |
| `services.openssh.authorizedKeysFiles` | list of string | `[]` | ibid. |
| `services.openssh.authorizedKeysInHomedir` | boolean | — | ibid. |
| `services.openssh.authorizedKeysCommand` | string | — | ibid. |
| `services.openssh.authorizedKeysCommandUser` | string | — | ibid. |
| `services.openssh.hostKeys` | list of (attribute set) | — | ibid. |
| `services.openssh.generateHostKeys` | boolean | — | ibid. |
| `services.openssh.listenAddresses` | list of (submodule) | `[]` | ibid. |
| `services.openssh.listenAddresses.*.addr` | null or string | `null` | ibid. |
| `services.openssh.listenAddresses.*.port` | null or 16-bit uint | `null` | ibid. |
| `services.openssh.startWhenNeeded` | boolean | **`false`** | ibid. |
| `services.openssh.extraConfig` | strings concatenated with `\n` | `""` | ibid. |
| `services.openssh.knownHosts` | attribute set of (submodule) | `{}` | ibid. |
| `security.sudo.enable` | boolean | — | [options](https://search.nixos.org/options?channel=unstable&query=security.sudo.enable) |
| `security.sudo.execWheelOnly` | boolean | — | ibid. |
| `security.sudo.defaultOptions` | list of string | — | ibid. |
| `security.sudo.extraRules` | list of (submodule) | `[]` | ibid. |
| `security.sudo.extraRules.*.users` / `.groups` / `.commands` / `.runAs` / `.host` | — | — | ibid. |
| `security.sudo.extraConfig` | strings concatenated with `\n` | `""` | ibid. |
| `security.sudo.configFile` | strings concatenated with `\n` | — | ibid. |
| `security.sudo.package` | package | — | ibid. |
| `security.sudo-rs.enable` | boolean | — | ibid. |
| `security.sudo-rs.execWheelOnly` | boolean | — | ibid. |
| `security.sudo-rs.extraRules` / `.extraConfig` / `.configFile` / `.package` | — | — | ibid. |
| `security.pam.enable` | boolean | — | [options](https://search.nixos.org/options?channel=unstable&query=security.pam.enable) |
| `security.pam.services` | attribute set of (submodule) | `{}` | ibid. |
| `security.pam.services.<name>.enable` | boolean | — | ibid. |
| `security.pam.services.<name>.failDelay.enable` / `.delay` | boolean / signed integer | — | ibid. |
| `security.pam.loginLimits` | list of (submodule) | `[]` | ibid. |
| `security.pam.loginLimits.*.domain` / `.type` / `.item` / `.value` | string / enum / enum / string-or-int | — | ibid. |
| `security.pam.oath.enable` / `.usersFile` / `.window` / `.digits` | — | — | ibid. |
| `security.pam.p11.enable` | boolean | — | ibid. |
| `security.pam.krb5.enable` | boolean | — | ibid. |
| `security.pam.package` | package | — | ibid. |

### 8.3 Firewall and networking

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `networking.firewall.enable` | boolean | **`true`** | [options](https://search.nixos.org/options?channel=unstable&query=networking.firewall.enable) |
| `networking.firewall.allowedTCPPorts` | list of 16-bit uint | `[]` | ibid. |
| `networking.firewall.allowedUDPPorts` | list of 16-bit uint | `[]` | ibid. |
| `networking.firewall.allowedTCPPortRanges` | list of attribute set (`{ from; to; }`) | `[]` | ibid. |
| `networking.firewall.allowedUDPPortRanges` | list of attribute set (`{ from; to; }`) | `[]` | ibid. |
| `networking.firewall.interfaces` | attribute set of (submodule) | `{}` | ibid. |
| `networking.firewall.interfaces.<name>.allowedTCPPorts` / `.allowedUDPPorts` / `.allowedTCPPortRanges` / `.allowedUDPPortRanges` | list | `[]` | ibid. |
| `networking.firewall.trustedInterfaces` | list of string | `[]` | ibid. |
| `networking.firewall.checkReversePath` | boolean or `"strict"` or `"loose"` | — | ibid. |
| `networking.firewall.backend` | `"iptables"` / `"nftables"` / `"firewalld"` | `iptables` | ibid. |
| `networking.firewall.extraCommands` | strings concatenated with `\n` | `""` | ibid. (iptables only) |
| `networking.firewall.extraPackages` | list of package | `[]` | ibid. |
| `networking.firewall.extraInputRules` | strings concatenated with `\n` | `""` | ibid. (nftables only) |
| `networking.firewall.extraForwardRules` | strings concatenated with `\n` | `""` | ibid. (nftables only) |
| `networking.firewall.extraReversePathFilterRules` | strings concatenated with `\n` | `""` | ibid. (nftables only) |
| `networking.firewall.extraStopCommands` | strings concatenated with `\n` | `""` | ibid. (iptables only) |
| `networking.firewall.filterForward` | boolean | `false` | ibid. (nftables only) |
| `networking.firewall.logRefusedConnections` | boolean | `false` | ibid. |
| `networking.firewall.logRefusedPackets` | boolean | `false` | ibid. |
| `networking.firewall.logRefusedUnicastsOnly` | boolean | `false` | ibid. |
| `networking.firewall.logReversePathDrops` | boolean | `false` | ibid. |
| `networking.firewall.rejectPackets` | boolean | `false` | ibid. |
| `networking.firewall.allowPing` | boolean | — | ibid. |
| `networking.firewall.pingLimit` | null or strings | `null` | ibid. |
| `networking.firewall.autoLoadConntrackHelpers` | boolean | `false` | ibid. |
| `networking.firewall.connectionTrackingModules` | list of string | `[]` | ibid. |
| `networking.firewall.package` | package | — | ibid. |
| `networking.hostName` | string (DNS-label regex) | — | [options](https://search.nixos.org/options?channel=unstable&query=networking.hostName) |
| `networking.domain` | null or string | `null` | ibid. |
| `networking.useDHCP` | boolean | `true` | ibid. |
| `networking.nftables.enable` | boolean | `false` | ibid. |
| `networking.usePredictableInterfaceNames` | boolean | — | [Manual](https://nixos.org/manual/nixos/unstable/#sec-changing-config) |

### 8.4 Nix daemon / store / GC

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `nix.settings` | open submodule of (Nix config atom or list of) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=nix.settings) |
| `nix.settings.trusted-users` | list of string | `["root"]` | [nix.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/nix.nix) |
| `nix.settings.trusted-public-keys` | list of string | `["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="]` | ibid. |
| `nix.settings.substituters` | list of string | `["https://cache.nixos.org/"]` | ibid. |
| `nix.settings.trusted-substituters` | list of string | `[]` | ibid. |
| `nix.settings.allowed-users` | list of string | `["*"]` | ibid. |
| `nix.settings.sandbox` | boolean or `"relaxed"` | `true` | ibid. |
| `nix.settings.require-sigs` | boolean | `true` | ibid. |
| `nix.settings.auto-optimise-store` | boolean | `false` | ibid. |
| `nix.settings.max-jobs` | signed integer or `"auto"` | `"auto"` | ibid. |
| `nix.settings.cores` | signed integer | — | ibid. |
| `nix.settings.extra-sandbox-paths` | list of string | `[]` | ibid. |
| `nix.settings.experimental-features` | list of string | `[]` | [options](https://search.nixos.org/options?channel=unstable&query=nix.settings.experimental-features) |
| `nix.settings.system-features` | list of string | `["nixos-test" "benchmark" "big-parallel" "kvm" "gccarch-<arch>"]` | [nix.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/nix.nix) |
| `nix.package` | package | — | [options](https://search.nixos.org/options?channel=unstable&query=nix.package) |
| `nix.registry` | attribute set of (submodule) | `{}` | ibid. |
| `nix.gc.automatic` | boolean | `false` | [options](https://search.nixos.org/options?channel=unstable&query=nix.gc.automatic) |
| `nix.gc.dates` | single-line string or list of string | — | ibid. |
| `nix.gc.options` | single-line string | `""` | ibid. |
| `nix.gc.persistent` | boolean | `true` | ibid. |
| `nix.gc.randomizedDelaySec` | single-line string | — | ibid. |
| `nix.optimise.automatic` | boolean | `false` | [options](https://search.nixos.org/options?channel=unstable&query=nix.optimise.automatic) |
| `nix.optimise.dates` | single-line string | — | ibid. |
| `nix.optimise.persistent` | boolean | `true` | ibid. |
| `nix.optimise.randomizedDelaySec` | single-line string | — | ibid. |

### 8.5 systemd

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `systemd.services` | attribute set of (submodule) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=systemd.services) |
| `systemd.services.<name>.serviceConfig` | attribute set of (systemd option) — **`[Service]` section** | `{}` | ibid. |
| `systemd.services.<name>.unitConfig` | attribute set of (systemd option) — **`[Unit]` section** | `{}` | ibid. |
| `systemd.services.<name>.path` | list of (package or string) | `[]` | ibid. |
| `systemd.services.<name>.environment` | attribute set of (null or string or absolute path or package) | `{}` | ibid. |
| `systemd.services.<name>.wantedBy` | list of string | `[]` | ibid. |
| `systemd.services.<name>.after` / `.before` | list of string | `[]` | ibid. |
| `systemd.services.<name>.requires` / `.requisite` / `.wants` / `.bindsTo` / `.conflicts` / `.partOf` | list of string | `[]` | ibid. |
| `systemd.services.<name>.script` | strings concatenated with `\n` | `""` | ibid. |
| `systemd.services.<name>.preStart` / `.postStart` / `.preStop` / `.postStop` / `.reload` | strings concatenated with `\n` | `""` | ibid. |
| `systemd.services.<name>.enable` | boolean | `true` | ibid. |
| `systemd.services.<name>.name` | string | — | ibid. |
| `systemd.services.<name>.startAt` | string or list of string | — | ibid. |
| `systemd.services.<name>.overrideStrategy` | `"asDropinIfExists"` / `"asDropin"` | — | ibid. |
| `systemd.services.<name>.confinement.enable` | boolean | `false` | ibid. |
| `systemd.services.<name>.confinement.mode` | `"full-apivfs"` / `"chroot-only"` | `"full-apivfs"` | ibid. |
| `systemd.services.<name>.confinement.packages` | list of (string or package) | `[]` | ibid. |
| `systemd.services.<name>.confinement.fullUnit` | boolean | `false` | ibid. |
| `systemd.services.<name>.enableStrictShellChecks` | boolean | `false` | ibid. |
| `systemd.services.<name>.notSocketActivated` | boolean | `false` | ibid. |
| `systemd.services.<name>.restartIfChanged` / `.stopIfChanged` / `.reloadIfChanged` | boolean | — | ibid. |
| `systemd.user.services` | attribute set of (submodule) | `{}` | [systemd/user.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/user.nix) |
| `systemd.tmpfiles.rules` | list of string | `[]` | [options](https://search.nixos.org/options?channel=unstable&query=systemd.tmpfiles.rules) |
| `systemd.tmpfiles.settings` | attribute set of attribute set of attribute set of (submodule) | `{}` | ibid. |
| `systemd.tmpfiles.packages` | list of package | `[]` | ibid. |
| `systemd.network.networks` | attribute set of (submodule) | `{}` | [options](https://search.nixos.org/options?channel=unstable&query=systemd.network.networks) |
| `systemd.network.networks.<name>.networkConfig` | attribute set of (systemd option) — `[Network]` | `{}` | ibid. |
| `systemd.network.networks.<name>.matchConfig` | attribute set of (systemd option) — `[Match]` | `{}` | ibid. |
| `systemd.network.networks.<name>.DHCP` | null or string | `null` | ibid. |
| `systemd.network.networks.<name>.address` | list of string | `[]` | ibid. |
| `systemd.network.links.<name>.matchConfig` / `.linkConfig` | attribute set of (systemd option) | `{}` | ibid. |
| `systemd.network.config.networkConfig` | attribute set of (systemd option) | `{}` | ibid. |

### 8.6 Docker, Podman, OCI containers

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `virtualisation.docker.enable` | boolean | `false` | [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix) |
| `virtualisation.docker.daemon.settings` | open submodule of (JSON value) | `{}` | ibid. |
| `virtualisation.docker.daemon.settings.live-restore` | boolean | `versionOlder stateVersion "24.11"` | ibid. |
| `virtualisation.docker.liveRestore` | submodule (alias) | — | ibid. |
| `virtualisation.docker.storageDriver` | null or enum (`aufs`/`btrfs`/`devicemapper`/`overlay`/`overlay2`/`zfs`) | `null` | ibid. |
| `virtualisation.docker.logDriver` | enum (`none`…`local`) | `"journald"` | ibid. |
| `virtualisation.docker.extraOptions` | separated string | `""` | ibid. |
| `virtualisation.docker.listenOptions` | list of string | `["/run/docker.sock"]` | ibid. |
| `virtualisation.docker.enableOnBoot` | boolean | `true` | ibid. |
| `virtualisation.docker.package` | package | — | ibid. |
| `virtualisation.docker.extraPackages` | list of package | `[]` | ibid. |
| `virtualisation.docker.autoPrune.enable` | boolean | `false` | ibid. |
| `virtualisation.docker.autoPrune.flags` | list of string | `[]` | ibid. |
| `virtualisation.docker.autoPrune.dates` | string | `"weekly"` | ibid. |
| `virtualisation.docker.autoPrune.persistent` | boolean | `true` | ibid. |
| `virtualisation.docker.autoPrune.randomizedDelaySec` | single-line string | `"0"` | ibid. |
| `virtualisation.docker.autoPrune.allVolumes.enable` | boolean | `false` | ibid. |
| `virtualisation.docker.autoPrune.allVolumes.flags` | list of string | `[]` | ibid. |
| `virtualisation.docker.rootless.enable` | boolean | `false` | ibid. |
| `virtualisation.docker.rootless.daemon.settings` | JSON value | `{}` | ibid. |
| `virtualisation.docker.rootless.setSocketVariable` | boolean | `false` | ibid. |
| `virtualisation.docker.rootless.package` / `.extraPackages` | package / list of package | — | ibid. |
| `virtualisation.docker.enableNvidia` | boolean (**deprecated**) | `false` | ibid. |
| `virtualisation.oci-containers.backend` | `"podman"` / `"docker"` | `"podman"` | [oci-containers.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/oci-containers.nix) |
| `virtualisation.oci-containers.containers` | attribute set of (submodule) | `{}` | ibid. |
| `virtualisation.oci-containers.containers.<name>.image` | string | — | ibid. |
| `virtualisation.oci-containers.containers.<name>.ports` | list of string | `[]` | ibid. |
| `virtualisation.oci-containers.containers.<name>.volumes` | list of string | `[]` | ibid. |
| `virtualisation.oci-containers.containers.<name>.autoStart` | boolean | — | ibid. |
| `virtualisation.oci-containers.containers.<name>.environment` | attribute set of string | `{}` | ibid. |
| `virtualisation.oci-containers.containers.<name>.extraOptions` | list of string | `[]` | ibid. |
| `virtualisation.oci-containers.containers.<name>.preRunExtraOptions` | list of string | `[]` | ibid. |
| `virtualisation.oci-containers.containers.<name>.user` | null or string | `null` | ibid. |
| `virtualisation.oci-containers.containers.<name>.privileged` | boolean | `false` | ibid. |
| `virtualisation.oci-containers.containers.<name>.capabilities` | lazy attribute set of (null or boolean) | `{}` | ibid. |
| `virtualisation.oci-containers.containers.<name>.pull` | `"always"`/`"missing"`/`"never"`/`"newer"` | — | ibid. |
| `virtualisation.oci-containers.containers.<name>.serviceName` | string | `"<backend>-<name>"` | ibid. |
| `virtualisation.oci-containers.containers.<name>.dependsOn` | list of string | `[]` | ibid. |
| `virtualisation.oci-containers.containers.<name>.hostname` / `.workdir` | null or string | `null` | ibid. |
| `virtualisation.oci-containers.containers.<name>.cmd` / `.entrypoint` | list of string / null or string | `[]` / `null` | ibid. |
| `virtualisation.oci-containers.containers.<name>.log-driver` | string | `"journald"` | ibid. |
| `virtualisation.oci-containers.containers.<name>.labels` | attribute set of string | `{}` | ibid. |
| `virtualisation.oci-containers.containers.<name>.imageFile` | null or path in the Nix store | `null` | ibid. |
| `virtualisation.oci-containers.containers.<name>.imageStream` | null or package | `null` | ibid. |
| `virtualisation.oci-containers.containers.<name>.podman.user` | string | — | ibid. |
| `virtualisation.oci-containers.containers.<name>.podman.sdnotify` | `"conmon"`/`"healthy"`/`"container"` | — | ibid. |
| `virtualisation.podman.enable` | boolean | `false` | [podman/default.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/podman/default.nix) |
| `virtualisation.podman.dockerSocket.enable` | boolean | `false` | ibid. |
| `virtualisation.podman.dockerCompat` | boolean | `false` | ibid. |

### 8.7 System-level and operations

| Option | Type | Default | Source |
| --- | --- | --- | --- |
| `system.stateVersion` | string | `config.system.nixos.release` | [options](https://search.nixos.org/options?channel=unstable&query=system.stateVersion) |
| `system.autoUpgrade.enable` | boolean | `false` | ibid. |
| `system.autoUpgrade.allowReboot` | boolean | `false` | ibid. |
| `system.autoUpgrade.channel` | null or string | `null` | ibid. |
| `system.activationScripts` | attribute set of (string or submodule) | `{}` | ibid. |
| `system.tools.nixos-rebuild.enableRun0Elevation` | boolean | `false` | ibid. |
| `environment.systemPackages` | list of package | `[]` | ibid. |
| `environment.memoryAllocator.provider` | enum (`libc`/`graphene-hardened`/`graphene-hardened-light`/`jemalloc`/`mimalloc`/`scudo`) | `"libc"` | ibid. |
| `security.apparmor.enable` | boolean | `false` | [apparmor.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/apparmor.nix) |
| `security.apparmor.policies` | attribute set of (submodule) | `{}` | ibid. |
| `security.apparmor.policies.<name>.profile` | strings concatenated with `\n` | — | ibid. |
| `security.apparmor.policies.<name>.path` | null or absolute path | — | ibid. |
| `security.apparmor.policies.<name>.state` | `"disable"`/`"complain"`/`"enforce"` | — | ibid. |
| `security.apparmor.includes` | attribute set of strings | `{}` | ibid. |
| `security.apparmor.packages` | list of package | `[]` | ibid. |
| `security.apparmor.enableCache` | boolean | `false` | ibid. |
| `security.apparmor.killUnconfinedConfinables` | boolean | `false` | ibid. |
| `security.audit.enable` | `false`/`true`/`"lock"` | `false` | [audit.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/audit.nix) |
| `security.audit.rules` | list of string | `[]` | ibid. |
| `security.audit.failureMode` | `"silent"`/`"printk"`/`"panic"` | — | ibid. |
| `security.audit.rateLimit` / `.backlogLimit` | signed integer | — | ibid. |
| `security.audit.package` | package | — | ibid. |
| `security.auditd.enable` | boolean | — | [auditd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/auditd.nix) |
| `security.auditd.settings` | open submodule | `{}` | ibid. |
| `security.lockKernelModules` | boolean | — | [options](https://search.nixos.org/options?channel=unstable&query=security.lockKernelModules) |
| `security.protectKernelImage` | boolean | — | ibid. |
| `security.allowSimultaneousMultithreading` | boolean | — | ibid. |
| `security.forcePageTableIsolation` | boolean | — | ibid. |
| `security.virtualisation.flushL1DataCache` | null/`"never"`/`"cond"`/`"always"` | `null` | ibid. |
| `services.fail2ban.enable` | boolean | `false` | [options](https://search.nixos.org/options?channel=unstable&query=services.fail2ban.enable) |
| `services.fail2ban.jails` | attribute set of (strings or submodule) | — | ibid. |
| `services.fail2ban.daemonSettings` | attribute set of INI section | `{}` | ibid. |
| `services.fail2ban.maxretry` | unsigned integer | — | ibid. |
| `services.fail2ban.bantime` | string | — | ibid. |
| `services.fail2ban.ignoreIP` | list of string | `[]` | ibid. |
| `services.fail2ban.banaction` / `.banaction-allports` | string | — | ibid. |
| `services.fail2ban.extraPackages` | list of package | `[]` | ibid. |
| `services.fail2ban.package` / `.packageFirewall` | package | — | ibid. |
| `services.fail2ban.bantime-increment.enable` | boolean | — | ibid. |
| `services.logind.enable` | boolean | — | [options](https://search.nixos.org/options?channel=unstable&query=services.logind.enable) |
| `services.logind.settings.Login` | open submodule of (systemd option) | `{}` | ibid. |
| `services.logind.settings.Login.KillUserProcesses` | boolean | **`false`** (nixpkgs override) | ibid. |
| `services.prometheus.enable` | boolean | `false` | [options](https://search.nixos.org/options?channel=unstable&query=services.prometheus.enable) |
| `services.prometheus.alertmanager.enable` | boolean | `false` | ibid. |
| `services.prometheus.alertmanager.port` | 16-bit uint | — | ibid. |
| `services.prometheus.alertmanager.openFirewall` | boolean | — | ibid. |

**Options accepted but NOT indexed (freeform parents) — use with the parent's type in mind:**

| Option | Parent | Accepted because | Source |
| --- | --- | --- | --- |
| `services.openssh.settings.MaxAuthTries` | `services.openssh.settings` | freeform submodule with `freeformType = settingsFormat.type` | [sshd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ssh/sshd.nix) |
| `services.openssh.settings.LoginGraceTime` | `services.openssh.settings` | ibid. | ibid. |
| `services.openssh.settings.ClientAliveInterval` / `.ClientAliveCountMax` | `services.openssh.settings` | ibid. | ibid. |
| `services.openssh.settings.AllowTcpForwarding` | `services.openssh.settings` | ibid. | ibid. |
| `services.openssh.settings.AuthenticationMethods` | `services.openssh.settings` | ibid. | ibid. |
| `boot.kernel.sysctl."<any sysctl>"` | `boot.kernel.sysctl` | open submodule of attribute set of (sysctl option value) | [options](https://search.nixos.org/options?channel=unstable&query=boot.kernel.sysctl) |
| `virtualisation.docker.daemon.settings."<any daemon.json key>"` | `virtualisation.docker.daemon.settings` | open submodule of (JSON value) | [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix) |
| `nix.settings."<any nix.conf key>"` | `nix.settings` | open submodule of (Nix config atom) | [nix.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/nix.nix) |
| `systemd.services.<name>.serviceConfig."<any [Service] directive>"` | `systemd.services.<name>.serviceConfig` | attribute set of (systemd option) | [options](https://search.nixos.org/options?channel=unstable&query=systemd.services) |

---

## 9. Security Hardening Checklist

Ordered by dependency: earlier items either enable or constrain later ones. Each item
cites the primary source that justifies it.

### Phase 0 — Foundations (do these first; everything else depends on them)

1. **Use a flake, and pin the nixpkgs input by commit.** Store the flake in git;
   the config is the source of truth and is reviewable. *Sources:*
   [`nixos-rebuild.8.scd`](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd) (`--flake`, `/etc/nixos/flake.nix` symlink convention);
   [nixpkgs/flake.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/flake.nix) (`nixosConfigurations`, `nixosModules` outputs).
2. **Set `system.stateVersion` once at install, and never bump it casually.**
   *Source:* `system.stateVersion` option description — *"Most users should never
   change this value after the initial install, for any reason"* and *"This value
   does not affect the Nixpkgs version your packages and OS are pulled from."*
   Also read the Manual's release notes for the target version first — the
   Tandoor Recipes entry shows a `stateVersion`-gated **security** remediation.
3. **Verify the workflow before touching the running host:**
   `nixos-rebuild build --flake .#host` → `nixos-rebuild build-vm --flake .#host` →
   `nixos-rebuild test --flake .#host` → `nixos-rebuild switch --flake .#host`.
   *Sources:* `nixos-rebuild.8.scd` (action semantics); NixOS Manual ("`test` … does
   not add it to the GRUB boot menu … if you reboot … you will automatically revert").
4. **Create a non-root admin user with an SSH key; add it to `wheel`.**
   *Sources:* `users.users`, `users.users.<name>.openssh.authorizedKeys.keys`.
5. **Never rely on an interactive credential for root.**
   `services.openssh.settings.PermitRootLogin` already defaults to the strict
   value, which permits key-only root login. *Source:* option default.
6. **Refuse every non-key authentication method.**
   In `services.openssh.settings`, set the directive that turns off the
   remaining interactive authentication methods (it defaults to `true`).
   *Source:* option default. Also `services.openssh.settings.KbdInteractiveAuthentication = false`
   so that keyboard-interactive cannot be used as a fallback.
7. **Keep the Nix daemon reachable only by trusted users.**
   `nix.settings.allowed-users = [ "@users" ]` — the NixOS Wiki's own hardening
   recipe. *Source:* [NixOS Wiki, NixOS Hardening](https://wiki.nixos.org/wiki/NixOS_Hardening).
8. **Keep the Nix trust model at its secure defaults and do not weaken them:**
   `nix.settings.sandbox = true` (default), `nix.settings.require-sigs = true`
   (default), `nix.settings.trusted-public-keys` = the `cache.nixos.org` key only.
   *Source:* `nixos/modules/config/nix.nix` defaults.
9. **Restrict `nix.settings.trusted-users`** to the minimum set. Trusted users can
   "import unsigned NARs" and specify extra binary caches — this is root-equivalent
   power over the store. *Source:* option description.
10. **Decide `users.mutableUsers` explicitly.** `false` gives a fully declarative
    system user database but **resets changed credentials on activation**; `true`
    merges and persists imperative changes. *Source:* `users.mutableUsers` option description.

### Phase 1 — Network perimeter

11. **Keep the firewall enabled** — it is on by default and blocks unauthorised TCP
    and UDP on both IPv4 and IPv6. *Source:* NixOS Manual, Firewall.
12. **Open the minimum port set** via `networking.firewall.allowedTCPPorts`
    (typically 22 and 443). Use `networking.firewall.interfaces.<name>.*` to scope
    ports to a specific interface. *Source:* `networking.firewall` options.
13. **Do not use `networking.firewall.trustedInterfaces` on a VPS's public
    interface.** It accepts traffic unconditionally. *Source:* option description.
14. **Enable reverse-path filtering** with
    `networking.firewall.checkReversePath = true` (strict) and
    `networking.firewall.logReversePathDrops = true`. *Source:* option descriptions.
    *Caveat:* `services.ivpn.enable` and `services.speedify.enable` both force this
    to `"loose"` — do not combine them with strict rp_filter.
15. **Leave `networking.firewall.rejectPackets = false`** (drop, not reject) — the
    option itself says *"Rejecting packets makes port scanning somewhat easier."*
16. **Leave `networking.firewall.autoLoadConntrackHelpers = false` and
    `networking.firewall.connectionTrackingModules = []`** — the option says
    *"As helpers can pose as a security risk, it is advised to set this to an empty
    list."*
17. **Pin the firewall backend explicitly** to `iptables` if Docker is enabled.
    *Source:* `networking.nftables.enable` — *"if you have Docker enabled you will
    not be able to use nftables without intervention. Docker uses iptables
    internally to setup NAT for containers."*
18. **Use `networking.firewall.extraCommands` only on the iptables backend**, and
    `extraInputRules` / `extraForwardRules` only on nftables. They are
    backend-specific. *Source:* option descriptions.

### Phase 2 — SSH

19. **Enable SSH socket activation**: `services.openssh.startWhenNeeded = true`.
    *Source:* option description — *"instead of having it permanently running as a
    daemon, systemd will start an instance for each incoming connection."*
20. **Pin the SSH listener** with `services.openssh.listenAddresses` if the VPS has a
    fixed address, and keep `services.openssh.ports = [ 22 ]` unless you have a
    reason not to. *Source:* option description; note *"setting this option won't
    automatically enable given ports in firewall configuration"* for
    `listenAddresses`.
21. **Leave `services.openssh.settings.X11Forwarding = false`** (already the default)
    and consider `AllowTcpForwarding = false` unless needed. *Source:* option
    default; `AllowTcpForwarding` via the freeform `settings` submodule.
22. **Keep `services.openssh.enableRecommendedAlgorithms = true`** so that NixOS's
    curated cipher/KEX/MAC set is used. *Source:* option description.
23. **Restrict who may log in** with `services.openssh.settings.AllowUsers`
    and/or `DenyGroups`. *Source:* option descriptions.
24. **Consider `services.openssh.authorizedKeysInHomedir = false`** so that only
    `/etc/ssh/authorized_keys.d` is trusted by default — that directory is
    Nix-managed and therefore reviewable in git. *Source:* option description.
25. **Use `services.openssh.authorizedKeysCommand` only with a dedicated,
    non-privileged user** — the option says the program *"must be owned by root,
    not writable by group or others"* and that `authorizedKeysCommandUser` *"is
    recommended to use a dedicated user that has no other role on the host."*
26. **Set `services.openssh.settings.LogLevel = "VERBOSE"`** so fail2ban can see
    failed logins. fail2ban's module sets this for you, but being explicit avoids
    surprise. *Source:* `services.fail2ban.jails` option description.
27. **Install fail2ban**: `services.fail2ban.enable = true`, and set
    `services.fail2ban.ignoreIP` to your own IP/VPN range to avoid self-lockout.
    Keep `services.fail2ban.packageFirewall` aligned with
    `networking.firewall.backend` (it defaults to matching it). *Sources:*
    `services.fail2ban.*` option descriptions.

### Phase 3 — Kernel and system

28. **Lock the kernel modules after boot**: `security.lockKernelModules = true`.
    *Source:* option description — *"Disable kernel module loading once the system
    is fully initialised."* **Docker caveat:** nixpkgs already adds `bridge`,
    `veth`, `br_netfilter` and `xt_nat` to `boot.kernelModules`, so Docker still
    works — but never add a module outside that list afterwards. *Source:*
    [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix).
29. **Protect the running kernel image**: `security.protectKernelImage = true`.
    *Source:* option description.
30. **Apply the Wiki's sysctl baseline** via `boot.kernel.sysctl` — `kptr_restrict=2`,
    `bpf_jit_enable=false`, `ftrace_enabled=false`, `io_uring_disabled=2`,
    strict `rp_filter`, `accept_redirects=false`, `send_redirects=false`,
    `log_martians=true`. *Source:* [NixOS Wiki, NixOS Hardening](https://wiki.nixos.org/wiki/NixOS_Hardening).
31. **Apply the kernel command line** baseline: `boot.kernelParams = [
    "slab_nomerge" "page_poison=1" "page_alloc.shuffle=1" "debugfs=off" ]`.
    *Source:* [NixOS Wiki, NixOS Hardening](https://wiki.nixos.org/wiki/NixOS_Hardening).
32. **Blacklist unnecessary kernel modules** with `boot.blacklistedKernelModules`.
    *Source:* option description + Wiki recipe.
33. **Do not fight Docker over `ip_forward`.** nixpkgs sets
    `net.ipv4.conf.all.forwarding = true` with `mkOverride 98`; your
    `boot.kernel.sysctl` value will be overridden. Instead, if the nftables backend
    is in use, control forwarding with `networking.firewall.filterForward`.
    *Source:* [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix)
    + `networking.firewall.filterForward`.
34. **Enable the audit subsystem** if you need it: `security.audit.enable = true`
    with `security.audit.rules`. Use the `"lock"` value only after testing —
    the option warns *"this will prevent you from changing your audit configuration
    until you restart"* and suggests *"test your configuration using build-vm
    beforehand."*
35. **Treat AppArmor as experimental.** `security.apparmor.enable = true` requires a
    reboot to activate and *"privileges stability over security"*. The Wiki says
    AppArmor on NixOS is *"not yet been properly integrated"*. *Sources:*
    `security.apparmor.enable` option description; [NixOS Wiki, Security](https://wiki.nixos.org/wiki/Security).
36. **Do not plan around SELinux.** The Wiki: *"proper integration does not exist."*
    *Source:* [NixOS Wiki, Security](https://wiki.nixos.org/wiki/Security).
37. **Harden individual services with `systemd.services.<name>.serviceConfig`.**
    Start from `systemd-analyze security <unit>` and apply the Wiki's annotated
    directive set: `ProtectSystem="strict"`, `ProtectHome=true`,
    `PrivateTmp=true`, `PrivateDevices=true`, `PrivateUsers=true`,
    `NoNewPrivileges=true`, `ProtectKernelTunables=true`,
    `ProtectKernelModules=true`, `ProtectControlGroups=true`,
    `RestrictSUIDSGID=true`, `RestrictRealtime=true`, `RestrictNamespaces=true`,
    `LockPersonality=true`, `SystemCallFilter=[ "@system-service" ]`,
    `CapabilityBoundingSet=""`, `SystemCallArchitectures="native"`,
    `MemoryDenyWriteExecute=true`, `RestrictAddressFamilies=[ "AF_UNIX" "AF_INET" "AF_INET6" ]`,
    `ReadWritePaths=[ … ]`. *Sources:*
    [NixOS Wiki, Systemd/Hardening](https://wiki.nixos.org/wiki/Systemd/Hardening);
    [systemd.exec(5)](https://man7.org/linux/man-pages/man5/systemd.exec.5.html).
    **Do not** apply this to `docker.service` — it needs broad host access.
38. **Use `systemd.services.<name>.path`** to control the service's `PATH`
    precisely instead of inheriting a wide one. *Source:* option description.
39. **Set `services.logind.settings.Login.KillUserProcesses = true`** if you do not
    rely on lingering user processes — note nixpkgs deliberately defaults it to
    `false` because tmux/screen/nohup/VNC would break. *Source:* option description.
40. **Consider `environment.memoryAllocator.provider = "scudo"`** (or
    `graphene-hardened`) for the whole system — the option warns of instability,
    so validate with `build-vm` first. *Source:* option description.
41. **Use `zramSwap.enable = true`** with `zramSwap.priority` above any disk swap.
    *Source:* `zramSwap.*` option descriptions.

### Phase 4 — Docker

42. **Understand that the `docker` group is root-equivalent** before granting it.
    Docker: *"The `docker` group grants root-level privileges to the user."*
    *Source:* [Docker post-install steps](https://docs.docker.com/engine/install/linux-postinstall/).
    Put **only** the specific operator account in `users.users.<name>.extraGroups`.
43. **Do not add `virtualisation.podman.dockerSocket.enable` or
    `virtualisation.podman.dockerCompat` alongside Docker** — both are hard build
    assertions against `virtualisation.docker.enable`. *Source:*
    [podman/default.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/podman/default.nix).
44. **Set `virtualisation.docker.storageDriver` explicitly.** The option says
    *"it is recommended to specify a storage driver explicitly, as docker's default
    varies over versions."* On ext4 root, `"overlay2"` is the natural choice.
    *Source:* option description.
45. **Cap container log growth.** nixpkgs defaults `logDriver` to `"journald"`, which
    avoids the `json-file` unbounded-growth problem upstream warns about. If you
    keep `json-file`, set `log-opts` with `max-size` / `max-file`. *Sources:*
    `virtualisation.docker.logDriver` option; [Docker logging drivers](https://docs.docker.com/engine/logging/configure/).
46. **Set `virtualisation.docker.daemon.settings` hardening keys that are safe on
    NixOS**: `icc = false`, `no-new-privileges = true`, `live-restore = true`
    (non-Swarm), `log-opts` caps. *Do not set `hosts`* — nixpkgs already sets
    `hosts = [ "fd://" ]` and upstream warns the daemon fails to start on a
    conflict. *Sources:* [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix);
    [dockerd reference](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file).
47. **Consider `userns-remap`** — upstream: it *"can help to mitigate the risks of
    container breakout"* but is *"not enabled by default"*. **Decide before pulling
    images.** *Source:* [Docker Engine security](https://docs.docker.com/engine/security/).
48. **Consider `virtualisation.docker.rootless.enable = true`** where the workload
    allows; note Portainer's caveat that rootless Docker *"has some limitations,
    and requires additional configuration"*. *Sources:*
    `virtualisation.docker.rootless.enable` option;
    [Portainer Docker install](https://docs.portainer.io/start/install-ce/server/docker/linux.md).
49. **Enable `virtualisation.docker.autoPrune.enable`** to keep the store from
    growing unbounded — but note it does **not** prune volumes unless
    `autoPrune.allVolumes.enable` is set, and pruning volumes can delete
    Portainer's `portainer_data`. *Source:* `virtualisation.docker.autoPrune.*`
    option descriptions.
50. **Never expose the Docker TCP API.** Upstream: *"Exposing the daemon API over
    HTTP without TLS is not permitted, and such a configuration causes the daemon
    to fail early on startup."* *Source:*
    [Docker Engine security](https://docs.docker.com/engine/security/).

### Phase 5 — Portainer

51. **Pin the Portainer version and the image digest.** Tag-only pinning
    (`portainer/portainer-ce:lts`) is a moving target — `lts` is a floating tag.
    Pin an exact release tag **and** the digest. *Source:*
    [Portainer requirements](https://docs.portainer.io/start/requirements-and-prerequisites.md)
    (version matrix) and [GitHub releases](https://github.com/portainer/portainer/releases).
52. **Pin the native binary by SHA256 if you use the binary install.** The official
    release publishes `portainer-<version>-linux-<arch>.tar.gz` and a matching
    `-checksum.txt` containing
    `SHA256 (portainer-2.45.3-linux-amd64.tar.gz) = ab4ed7d58855f37d94c58d0a4316da5a1c13348269268a64486664a04de3b6a1`.
    *Source:* [release 2.45.3](https://github.com/portainer/portainer/releases/tag/2.45.3).
53. **Expose only 9443 (and 8000 only if you use Edge Agents).** Portainer's own
    requirements page lists exactly these. Do not expose the legacy HTTP port 9000
    — Portainer frames it as *"for legacy reasons"*. *Source:*
    [Portainer requirements](https://docs.portainer.io/start/requirements-and-prerequisites.md);
    [Portainer Docker install](https://docs.portainer.io/start/install-ce/server/docker/linux.md).
54. **Publish Portainer's port to loopback and front it with a reverse proxy** —
    because published container ports bypass the NixOS firewall. *Source:*
    `virtualisation.oci-containers.containers.<name>.ports` option description.
55. **Use the setup token for first-time setup.**
    The token *"exists to protect a freshly started instance from being claimed by
    someone other than the intended administrator"*, and must be used within
    5 minutes. Portainer also accepts the administrator's credentials on the
    command line, which is *"the recommended approach for managed or marketplace
    installs where you may not have direct access to the server logs"* — but that
    would put the credentials in the world-readable systemd unit, so this
    configuration uses the token instead.
    *Source:* [Portainer setup-token FAQ](https://docs.portainer.io/faqs/installing/setup-token.md).
56. **Provide your own TLS certificate** rather than relying on the self-signed
    default, if Portainer will be reached over a network you do not control.
    *Source:* [Portainer Docker install](https://docs.portainer.io/start/install-ce/server/docker/linux.md)
    and [Portainer SSL docs](https://docs.portainer.io/advanced/ssl.md).
57. **Persist `portainer_data` on durable storage and back it up.** Portainer:
    *"The Portainer Server requires persistent storage in order to maintain the
    database and configuration information it needs to function."* *Source:*
    [Portainer requirements](https://docs.portainer.io/start/requirements-and-prerequisites.md).
58. **Treat the `docker.sock` mount as granting root on the host** and be explicit
    about it — Portainer is designed to have it, but it means compromise of
    Portainer is compromise of the host. *Sources:*
    [Portainer Docker install](https://docs.portainer.io/start/install-ce/server/docker/linux.md);
    [Docker Engine security](https://docs.docker.com/engine/security/).

### Phase 6 — Operations

59. **Enable automatic garbage collection**: `nix.gc.automatic = true` with
    `nix.gc.dates` weekly — *"For most desktop and server systems a sufficient
    garbage collection is once a week."* *Source:* `nix.gc.dates` option description.
60. **Leave `nix.settings.auto-optimise-store = false`** (the default). It is a
    disk-space optimisation, not a hardening control, and the NixOS Wiki does not
    list it as one. See §10. *Source:* `nix.settings.auto-optimise-store` option.
61. **Decide on `system.autoUpgrade.enable` deliberately.** It runs
    `nixos-rebuild switch --upgrade` daily; `system.autoUpgrade.allowReboot` adds
    an automatic reboot when the kernel/initrd changed. For a VPS, automatic
    reboots can be an availability risk; prefer a controlled upgrade window and
    `system.autoUpgrade.channel` pinned to a specific channel URI. *Source:*
    `system.autoUpgrade.*` options; NixOS Manual, Automatic Upgrades.
62. **Back up the flake in git** — the configuration is the source of truth and
    `/etc` is regenerated from the store on every activation. *Source:* the NixOS
    Manual's description of `/etc/nixos/configuration.nix` and the store-backed
    `/etc`.
63. **Monitor.** `services.prometheus.enable = true` for the exporter stack;
    `services.prometheus.alertmanager.enable = true` for alerting. Note the
    `networking.firewall.allowedTCPPorts` requirement — Prometheus and
    Alertmanager do not open the firewall automatically unless
    `services.prometheus.alertmanager.openFirewall` is set. *Source:*
    `services.prometheus.*` options.
64. **Use `systemd.tmpfiles.rules` for volatile file lifecycles** rather than
    ad-hoc cron. *Source:* `systemd.tmpfiles.rules` option description.
65. **Keep activation scripts idempotent and fast** —
    `system.activationScripts` *"is executed every time you boot the system or run
    nixos-rebuild, so it's important that they are idempotent and fast."*
    *Source:* option description.

---

## 10. Unverified / Commonly Repeated But Unsourced

The following practices appear widely in hardening guides. **None of them could be
tied to a primary source in the sources consulted**, and they are therefore *not*
recommended in this document on the strength of a citation. Some have a
partial primary-source basis; the note says which.

| Practice | Status | Note |
| --- | --- | --- |
| `networking.firewall.allowedTCPPorts = [ 22 80 443 ]` as a "standard VPS hardening" baseline | **Community convention, no primary source** for the specific list | The *mechanism* is primary-sourced; the specific port list is an operator decision. |
| `boot.kernel.sysctl."kernel.dmesg_restrict" = 1` | **Community convention, no primary source.** The sysctl is a real Linux parameter and is settable via the freeform `boot.kernel.sysctl`, but it is **not** in the NixOS Wiki's hardening list | It is a legitimate control; it simply lacks first-party NixOS endorsement in the sources consulted. |
| `boot.kernel.sysctl."kernel.yama.ptrace_scope" = 1` | **Community convention, no primary source** (same situation as above) | |
| `boot.kernel.sysctl."fs.protected_hardlinks" = 1` | **Community convention, no primary source** | Modern kernels default this on; the NixOS Wiki does not list it. |
| `boot.kernel.sysctl."net.ipv4.tcp_syncookies" = 1` | **Community convention, no primary source** | |
| `boot.kernel.sysctl."net.ipv4.ip_forward" = 0` on a Docker host | **Impossible, and misleading advice** | nixpkgs overrides it with `mkOverride 98` to `true` whenever `virtualisation.docker.enable` is set. *Primary source:* [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix). |
| `nix.settings.auto-optimise-store = true` as a security measure | **Community convention, no primary source** | The option is *"If set to true, Nix automatically detects files in the store that have identical contents, and replaces them with hard links to a single copy. This saves disk space."* It is a **disk-space** control, not a security one, and defaults to `false`. The NixOS Wiki's hardening page does not list it. |
| `nix.gc.options = "--delete-old"`, `"-d"` etc. | **Community convention, no primary source** | `nix.gc.options` exists and takes a string passed to `nix-collect-garbage`; the *specific flags* are operator choices, not NixOS guidance. |
| "Run Docker with `icc=false` and `no-new-privileges`" | **Primary source exists, but not as a NixOS recipe** | The `daemon.json` keys are primary-sourced (Docker docs); the NixOS *expression* of them is our own mapping via the freeform `virtualisation.docker.daemon.settings`. |
| "Never expose Portainer's agent port 9000" | **Partially sourced, and the framing is wrong** | Portainer's documented **Agent** port is **9001**, and the **legacy HTTP UI** port is **9000**. The official docs contain no dedicated security warning about 9000; they label it legacy. See §11. |
| "Put the NixOS config in git" | **Community convention, no primary source** — though it follows from the fact that the config is a Nix expression evaluated into the store | No first-party NixOS statement mandating git was found in the sources consulted. |
| "Use `home-manager` on a server" | **Community convention, no primary source** for a *server* | Out of scope for a headless VPS; not recommended in this document. |
| `security.suid`, `security.protectedSysctl`, `security.denyNewPrivileges`, `security.patches`, `security.rngseed`, `security.privileges`, `security.rekernel`, `security.firewall` | **Do not exist** — verified NOT FOUND on unstable | These are the most common hallucinated NixOS security options. See §4.2. |
| `nix.build-users-group`, `nix.path-info` | **Do not exist** — verified NOT FOUND on unstable | |
| `services.monitoring` | **Does not exist** — verified NOT FOUND | Use `services.prometheus.*`. |
| `virtualisation.docker.portBindings` / `.openFirewall` / `.allowedRegistries` / `.allowedUsers` | **Do not exist** — verified NOT FOUND | |

---

## 11. Disagreements and Ambiguities

Places where the primary sources are inconsistent, ambiguous, or where the brief's
premise turned out to be wrong:

1. **The brief's "unstable (26.11)" does not exist as a channel.** The live channel
   index reports 25.11, **26.05 (stable)**, and `nixos-unstable`. There is no
   `nixos-26.11`. Everything here is verified against `nixos-unstable`. *Sources:*
   `nixos` MCP `channels` action; [channels.nixos.org](https://channels.nixos.org/).

2. **`security.firewall` does not exist; the firewall is `networking.firewall`.**
   The brief lists `security.firewall.*` extensively. `networking.firewall` has
   `allowedTCPPorts`, `allowedUDPPorts`, `allowedTCPPortRanges`,
   `allowedUDPPortRanges`, `enable`, `interfaces`, `trustedInterfaces`,
   `checkReversePath`, `extraCommands` — but **not** `logChanges` (the real names
   are `logRefusedConnections` / `logRefusedPackets` / `logRefusedUnicastsOnly`)
   and **not** `forwardPorts` (the closest is `filterForward`, nftables-only).

3. **`virtualisation.docker.daemonSettings` does not exist; the option is
   `virtualisation.docker.daemon.settings`.** The brief asked for confirmation of
   the exact name and shape: it is `daemon.settings`, an **open submodule of (JSON
   value)**, so it is a freeform attribute set serialized to `daemon.json` by
   `pkgs.formats.json`. Its only declared key is `live-restore`.

4. **The brief's claim that `ExecStart` "needs `--config-file`" is correct as a
   rationale but wrong as a requirement.** nixpkgs already passes
   `--config-file=${daemonSettingsFile}` (a read-only store path). Overriding
   `ExecStart` would break the `daemon.json` wiring. *Source:*
   [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix).

5. **`boot.initrd.systemd` no longer has an `enable` flag.** The scripted initrd was
   removed (`mkRemovedOptionModule … "Scripted initrd has been removed."`). The
   initrd is systemd-based; the `boot.initrd.systemd` submodule now holds content
   and network options only. *Source:*
   [initrd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/initrd.nix).

6. **`virtualisation.docker` and `virtualisation.oci-containers` do not conflict on
   socket units.** They create *different* units (`docker.socket` group `docker`,
   `podman.socket` group `podman`). The actual hard conflicts are the two
   **assertions** in the podman module: `virtualisation.podman.dockerCompat` and
   `virtualisation.podman.dockerSocket.enable` both assert
   `!config.virtualisation.docker.enable`. *Source:*
   [podman/default.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/podman/default.nix).

7. **Portainer's official docs do not document a binary/systemd install.** The
   documented Linux installs are Docker, Docker Swarm, Podman and Kubernetes.
   However the upstream repo *does* ship `distribution/portainer.service` and
   `distribution/portainer.spec`, so a native-binary install is feasible and
   citable — it is just undocumented by Portainer. *Sources:*
   [docs.portainer.io/llms.txt](https://docs.portainer.io/llms.txt);
   [portainer.service](https://github.com/portainer/portainer/blob/develop/distribution/portainer.service).

8. **Portainer's agent port naming is ambiguous in common usage.** Portainer's
   requirements page lists **9001** as the *Agent* port and **9443**/**8000** as
   the Server ports. **9000** is the *legacy HTTP UI* port, described in the
   install docs only as *"If you require HTTP port `9000` open for legacy
   reasons"*. The official docs contain **no** dedicated security warning about
   port 9000 or about exposing the Agent port. The practical guidance (close 9000,
   close 8000 unless using Edge Agents, keep 9001 reachable only *from* the
   Portainer Server) follows from the requirements page's port table, not from an
   explicit warning. *Source:*
   [Portainer requirements](https://docs.portainer.io/start/requirements-and-prerequisites.md).

9. **There is no `portainer` package in nixpkgs.** The only index matches are the
   Python clients `pyportainer`. A native-binary install therefore needs
   `pkgs.fetchurl` against the official release tarball, pinned by the SHA256 in
   Portainer's own `-checksum.txt` file.

10. **`services.openssh.settings` is freeform, so some useful keys are unindexed.**
    `MaxAuthTries`, `LoginGraceTime`, `ClientAliveInterval`,
    `AllowTcpForwarding` etc. are valid and rendered into `sshd_config`, but a
    lookup for them returns "not found" because only *declared* sub-options are
    indexed. *Source:* `freeformType = settingsFormat.type` in
    [sshd.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ssh/sshd.nix).

11. **The NixOS Manual and the `nixos-rebuild` man page differ in `nixos-rebuild`
    feature set.** The Manual describes the classic shell implementation
    (`switch`/`boot`/`test`/`build`/`repl`/`build-vm`); the nixpkgs man page
    describes the Python `nixos-rebuild-ng` with additional actions
    (`dry-build`, `dry-activate`, `list-generations`) and options
    (`--target-host`, `--elevate`, `--specialisation`). The unstable Manual has
    not caught up. *Sources:* [NixOS Manual](https://nixos.org/manual/nixos/unstable/#sec-changing-config);
    [nixos-rebuild.8.scd](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd).

12. **`nixos-rebuild --flake` semantics differ between the Manual and the man
    page.** The Manual only mentions `--flake` for `nixos-install` and
    `nixos-generate-config`. The man page is authoritative for `nixos-rebuild`
    itself: `--flake` defaults to the directory containing the symlink
    `/etc/nixos/flake.nix`, and the flake **must** expose
    `nixosConfigurations.<name>`. *Sources:* ibid.

13. **Docker's `daemon.json` conflicts are fatal, and nixpkgs pre-seeds several
    keys.** nixpkgs sets `group`, `hosts`, `log-driver` and (conditionally)
    `storage-driver` inside `daemon.settings`. Setting `hosts` yourself is
    pointless and upstream warns the daemon fails to start on a flag/file
    conflict. *Sources:* [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix);
    [dockerd reference](https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file).

14. **Docker's default `log-driver` differs between upstream and nixpkgs.**
    Upstream's `dockerd` default is `json-file`; nixpkgs' `virtualisation.docker.logDriver`
    defaults to `"journald"`. This is a **benefit** on NixOS (journald rotates),
    but it means a config written from upstream docs will not match nixpkgs
    behaviour. *Sources:* [dockerd reference](https://docs.docker.com/reference/cli/dockerd/);
    [docker.nix](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix).

15. **Container-published ports bypass the NixOS firewall** — stated for the
    `virtualisation.oci-containers` module. Docker's own `-p` mechanism has the
    same effect because Docker inserts DNAT rules ahead of the firewall's input
    chain. *Sources:*
    `virtualisation.oci-containers.containers.<name>.ports` option description;
    upstream behaviour described in the Docker daemon-configuration docs.

---

## 12. Citation Table

| # | Source | URL | What it supports |
| --- | --- | --- | --- |
| S1 | NixOS option index (`nixos-unstable`) via the `nixos` MCP server | `https://search.nixos.org/options?channel=unstable` | Existence, exact type and default of every option in §8; the "verified absent" list in §4.2 |
| S2 | NixOS Manual (unstable) — "Changing the Configuration" / "Upgrading NixOS" | https://nixos.org/manual/nixos/unstable/#sec-changing-config | `nixos-rebuild` action semantics; `system.autoUpgrade.*`; channel guidance; option-value syntax; `build-vm` caveats; `networking.firewall` example |
| S3 | NixOS Manual (unstable) — "Firewall" | https://nixos.org/manual/nixos/unstable/#sec-firewall | Firewall enabled by default; `allowedTCPPorts` / `allowedUDPPorts` / `allowedTCPPortRanges` / `allowedUDPPortRanges`; SSH port auto-open; predictable interface names |
| S4 | NixOS Manual (unstable) — "Writing NixOS Modules" (State revision) | https://nixos.org/manual/nixos/unstable/#sec-changing-config | `system.stateVersion` vs `stateRevision`; the rule that modules should not consume `system.stateVersion` |
| S5 | NixOS Wiki — Security | https://wiki.nixos.org/wiki/Security | SELinux "proper integration does not exist"; AppArmor "not yet been properly integrated" (April 2026); LUKS support; multi-user install; firewall enabled by default |
| S6 | NixOS Wiki — NixOS Hardening | https://wiki.nixos.org/wiki/NixOS_Hardening | `security.lockKernelModules`, `security.protectKernelImage`, `security.allowSimultaneousMultithreading`, `security.forcePageTableIsolation`, `security.virtualisation.flushL1DataCache`, `environment.memoryAllocator.provider`; the canonical sysctl and `boot.kernelParams` baselines; `nix.settings.allowed-users = [ "@users" ]`; `boot.blacklistedKernelModules` |
| S7 | NixOS Wiki — Systemd/Hardening | https://wiki.nixos.org/wiki/Systemd/Hardening | The annotated hardened-service-unit example; every `systemd.services.<name>.serviceConfig` directive and its rationale; `systemd-analyze security` as the entry method |
| S8 | nixpkgs — `nixos/modules/virtualisation/docker.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/docker.nix | `virtualisation.docker.*` exact options and defaults; `--config-file` already set by nixpkgs; `docker.socket` `SocketMode`/`SocketUser`/`SocketGroup`; `after`/`requires`; `mkOverride 98` IP-forwarding override; pre-seeded `daemon.settings` |
| S9 | nixpkgs — `nixos/modules/virtualisation/oci-containers.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/oci-containers.nix | `virtualisation.oci-containers.*`; *"Publishing a port bypasses the NixOS firewall"*; backend-conditional `after`/`path` |
| S10 | nixpkgs — `nixos/modules/virtualisation/podman/default.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/virtualisation/podman/default.nix | The two hard assertions against `virtualisation.docker.enable`; `podman.socket` group `podman`; `dockerSocket.enable` / `dockerCompat` |
| S11 | nixpkgs — `nixos/modules/services/networking/ssh/sshd.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/ssh/sshd.nix | `services.openssh.settings` freeform type; declared sshd_config keys; `users.users.<name>.openssh.authorizedKeys`; `services.openssh.startWhenNeeded` |
| S12 | nixpkgs — `nixos/modules/config/nix.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/nix.nix | `nix.settings` freeform type; `legacyConfMappings`; the actual defaults for `trusted-users`, `trusted-public-keys`, `substituters`, `sandbox`, `require-sigs`, `auto-optimise-store`, `allowed-users` |
| S13 | nixpkgs — `nixos/modules/config/users-groups.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/config/users-groups.nix | `users.users.<name>.*` option names; the "no root/wheel credential or key" assertion and its escape hatch |
| S14 | nixpkgs — `nixos/modules/system/boot/systemd/initrd.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/initrd.nix | `boot.initrd.systemd.enable` **removed**; the current `boot.initrd.systemd` content options |
| S15 | nixpkgs — `nixos/modules/system/boot/systemd/user.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/system/boot/systemd/user.nix | `systemd.user.services` uses the same submodule type as `systemd.services` |
| S16 | nixpkgs — `nixos/modules/tasks/network-interfaces-systemd.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/tasks/network-interfaces-systemd.nix | `systemd.network.networks.<name>.networkConfig` / `.matchConfig`; per-section `*Config` options |
| S17 | nixpkgs — `nixos/modules/security/apparmor.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/apparmor.nix | `security.apparmor.*`; reboot requirement; "privileges stability over security" |
| S18 | nixpkgs — `nixos/modules/security/audit.nix` / `auditd.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/audit.nix | `security.audit.*`; `security.auditd.*` |
| S19 | nixpkgs — `nixos/modules/security/pam.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/pam.nix | `security.pam.*` including `loginLimits` and the per-service submodule |
| S20 | nixpkgs — `nixos/modules/security/sudo.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/security/sudo.nix | `security.sudo.*` and `security.sudo-rs.*` |
| S21 | nixpkgs — `nixos/modules/services/networking/firewall.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/networking/firewall.nix | `networking.firewall.*` implementations and backend-specific `extra*` options |
| S22 | nixpkgs — `flake.nix` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/flake.nix | `nixosConfigurations` and `nixosModules` flake outputs |
| S23 | nixpkgs — `pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd` | https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/ni/nixos-rebuild-ng/nixos-rebuild.8.scd | `--flake` semantics and defaults; all actions and options; `/etc/nixos/flake.nix` symlink convention; `--target-host`/`--build-host`/`--elevate`/`--specialisation`/`--rollback` |
| S24 | Nix Manual (stable) — Flakes (`nix3-flake(1)`) | https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html | `nixConfig` semantics and the allow-list settable without `--accept-flake-config`; flake input/`outputs` model |
| S25 | Docker Engine — Security | https://docs.docker.com/engine/security/ | "Docker daemon attack surface"; root-equivalence of daemon control; capabilities model; `userns-remap`; AppArmor/SELinux interaction |
| S26 | Docker Engine — Linux post-installation steps | https://docs.docker.com/engine/install/linux-postinstall/ | *"The `docker` group grants root-level privileges to the user"*; shared group credential caveats; systemd boot; `json-file` growth warning |
| S27 | Docker Engine — Protect the Docker daemon socket | https://docs.docker.com/engine/security/protect-access/ | SSH/TLS socket access; mTLS; *"gives them root access to the machine hosting the daemon"* |
| S28 | Docker — `dockerd` reference (daemon configuration file) | https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file | Every `daemon.json` key in §5.4; the flag/file conflict rule; the `hosts`/`-H` conflict warning; `dockerd --validate` |
| S29 | Docker — Configure the Docker daemon | https://docs.docker.com/engine/daemon/ | Default config-file location; `--config-file`; `/var/lib/docker` data root |
| S30 | Docker — Logging drivers | https://docs.docker.com/engine/logging/configure/ | `log-driver` / `log-opts`; `max-size` / `max-file` rotation |
| S31 | Portainer — Install CE with Docker on Linux | https://docs.portainer.io/start/install-ce/server/docker/linux.md | The canonical `docker run` command; `portainer_data` volume; `docker.sock` mount; self-signed TLS default; legacy port 9000 |
| S32 | Portainer — Install CE with Podman on Linux | https://docs.portainer.io/start/install-ce/server/podman/linux.md | The Podman command (`--privileged`, `podman.sock`); "Portainer manages Podman through Podman's Docker-compatible API … not a native Podman integration" |
| S33 | Portainer — Requirements and prerequisites | https://docs.portainer.io/start/requirements-and-prerequisites.md | The version × Docker × Kubernetes × Podman support matrix; the exact port table (9443 / 8000 / 9001); the persistent-storage requirement |
| S34 | Portainer — Setup token FAQ | https://docs.portainer.io/faqs/installing/setup-token.md | Setup-token semantics; 5-minute window; the command-line credential flags; `--no-setup-token` |
| S35 | Portainer — Agent connectivity FAQ | https://docs.portainer.io/faqs/getting-started/how-does-portainer-secure-connectivity-to-and-from-agents-and-edge-agents.md | Agent claim handshake; `AGENT_SECRET`; Edge Agent mTLS + rotating key |
| S36 | Portainer — Documentation index (`llms.txt`) | https://docs.portainer.io/llms.txt | The **complete** list of documented install methods; the absence of a binary/systemd install page |
| S37 | Portainer upstream — `distribution/portainer.service` | https://github.com/portainer/portainer/blob/develop/distribution/portainer.service | The official systemd unit (`Environment=ASSETS=/usr/share/portainer`, `DBFILES=/var/lib/portainer`, `ExecStart=/usr/sbin/portainer -a $ASSETS -d $DBFILES`) |
| S38 | Portainer upstream — `distribution/portainer.spec` | https://github.com/portainer/portainer/blob/develop/distribution/portainer.spec | The canonical on-disk layout (binary, `public/` assets, DB path) |
| S39 | Portainer GitHub Releases API — latest | https://api.github.com/repos/portainer/portainer/releases/latest | Release tag `2.45.3`, publication date, per-arch tarballs and `-checksum.txt` assets |
| S40 | Portainer release 2.45.3 | https://github.com/portainer/portainer/releases/tag/2.45.3 | The official SHA256 checksum file content |
| S41 | systemd — `systemd.exec(5)` | https://man7.org/linux/man-pages/man5/systemd.exec.5.html | Existence and semantics of every `ProtectSystem=`, `ProtectHome=`, `NoNewPrivileges=`, `PrivateTmp=`, `RestrictAddressFamilies=`, `CapabilityBoundingSet=`, `ReadWritePaths=`, `SystemCallFilter=`, `DevicePolicy=`, `MemoryDenyWriteExecute=` … directive |
| S42 | systemd — `systemd.resource-control(5)` | https://man7.org/linux/man-pages/man5/systemd.resource-control.5.html | `IPAddressDeny=` / `IPAddressAllow=` (which live here, **not** in `systemd.exec(5)`); `CPUQuota=`, `MemoryMax=`, `TasksMax=` |
| S43 | NixOS channel index | https://channels.nixos.org/ | The actual channel list (25.11, 26.05 stable, unstable) behind the "26.11" premise |

---

*Research performed against nixpkgs `nixos-unstable` (branch HEAD
`31ecbaca1bdefa45dffc409f0250bd8039ea0010`) on 2026-10-30. All option
existences, types and defaults were resolved against the live official option
index; module-source citations point at the `nixos-unstable` branch.*
