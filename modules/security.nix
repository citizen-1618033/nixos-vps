# Security hardening for this VPS.
#
# Every option used here was verified against the nixpkgs `nixos-26.05` branch.
# The reasoning and the primary sources behind each decision are written up in
# docs/SECURITY.md; the research that preceded this file is in
# docs/research/nixos-vps-security-hardening.md.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # ==========================================================================
  # Network perimeter
  # ==========================================================================
  networking.firewall = {
    enable = true;

    # Only SSH is opened here. Caddy opens 80 and 443 for itself via
    # `services.caddy.openFirewall` (see modules/proxy.nix).
    allowedTCPPorts = [ 22 ];

    # Reverse-path filtering. This VPS has a single network interface, so the
    # default route always points back at the interface a packet arrived on
    # and strict mode is safe. If the provider ever gives you a second
    # interface with asymmetric routing, relax this to "loose" together with
    # the rp_filter sysctls below.
    checkReversePath = "strict";

    # Log rejected connections to the kernel log (journalctl -k). Needed for
    # detection; also what fail2ban and any external log shipper read.
    logRefusedConnections = true;
    logRefusedPackets = false;

    # Drop instead of reject. Rejecting makes port scanning easier because
    # the host answers with a "connection refused" instead of silence.
    rejectPackets = false;

    allowPing = true;
  };

  # nftables is deliberately NOT enabled. Docker uses iptables internally to
  # set up NAT for containers, and the two do not mix without manual
  # intervention. Docker's own module warning:
  #   "if you have Docker enabled you will not be able to use nftables without
  #    intervention."
  networking.nftables.enable = false;

  # ==========================================================================
  # Kernel
  # ==========================================================================
  # Baseline from the NixOS Wiki hardening page
  # (https://wiki.nixos.org/wiki/NixOS_Hardening).
  boot.kernel.sysctl = {
    # Do not expose kernel pointers to userspace.
    "kernel.kptr_restrict" = 2;

    # Do not compile BPF programs to native code.
    "net.core.bpf_jit_enable" = false;

    # No kernel function tracing.
    "kernel.ftrace_enabled" = false;

    # Disable io_uring for unprivileged processes (2 = privileged callers may
    # still use it). Containers are already restricted by Docker's default
    # seccomp profile.
    "kernel.io_uring_disabled" = 2;

    # Log packets with a martian source address and drop spoofed sources.
    "net.ipv4.conf.all.log_martians" = true;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.log_martians" = true;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = true;

    # A router must not accept or emit redirects.
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.all.secure_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv4.conf.default.secure_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv6.conf.default.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
  };

  # No kernel module loading once the system has finished booting. This closes
  # a common container-escape and rootkit path. nixpkgs adds bridge, veth,
  # br_netfilter and xt_nat for Docker, and modules/host.nix loads the virtio
  # modules explicitly, so this is safe. Takes effect on the next reboot.
  security.lockKernelModules = true;

  # ==========================================================================
  # SSH brute-force protection
  # ==========================================================================
  services.fail2ban = {
    enable = true;

    # Failures allowed before a ban.
    maxretry = 3;

    # Base ban duration.
    bantime = "1h";

    # Repeat offenders get progressively longer bans, capped at one day.
    bantime-increment = {
      enable = true;
      factor = "2";
      maxtime = "1d";
    };

    # Add your own fixed IP address or VPN range here so you cannot lock
    # yourself out. The NixOS default already exempts 127.0.0.1 and ::1.
    ignoreIP = [ ];
  };

  # NixOS ships a default `sshd` jail and sets LogLevel to VERBOSE when
  # fail2ban is enabled, which is what the jail needs to observe failures.
  services.openssh.settings = {
    X11Forwarding = false;
    MaxAuthTries = 3;
    LoginGraceTime = 30;

    # Disconnect idle sessions; also bounds how long a half-open connection
    # can occupy a slot.
    ClientAliveInterval = 300;
    ClientAliveCountMax = 2;
  };

  # ==========================================================================
  # Nix store
  # ==========================================================================
  nix.settings = {
    # Build in a sandbox. This is the NixOS default; stated explicitly because
    # it is one of the most valuable boundaries on the box.
    sandbox = true;

    # Hard-link identical store paths instead of storing them twice. On a
    # small VPS disk this is the difference between a comfortable and a full
    # filesystem.
    auto-optimise-store = true;

    # Only root may use the privileged Nix daemon operations.
    trusted-users = [ "root" ];

    # The official cache.nixos.org signing key. NixOS sets this by default;
    # restating it makes the trust boundary explicit.
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };

  # Collect garbage automatically. Docker images and build cache are not in
  # the Nix store, so this only affects Nix itself.
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 30d";
    persistent = true;
  };

  # ==========================================================================
  # Logging
  # ==========================================================================
  # nixpkgs defaults Docker's log driver to `journald`, so every container's
  # stdout/stderr ends up in the systemd journal. Cap it, otherwise a chatty
  # application fills the root filesystem.
  services.journald.extraConfig = ''
    SystemMaxUse=512M
    SystemKeepFree=1G
    MaxRetentionSec=1month
  '';

  # ==========================================================================
  # Automatic upgrades
  # ==========================================================================
  # Off on purpose. The auto-upgrade timer runs `nixos-rebuild switch
  # --upgrade`, which resolves against a *channel*, not against this flake,
  # and would silently drift the machine off the pinned configuration. The
  # supported procedure for a flake-based config is documented in
  # docs/DEPLOY.md: `nix flake update` followed by an explicit rebuild.
  system.autoUpgrade.enable = false;
}
