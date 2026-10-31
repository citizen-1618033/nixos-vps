# Entry point for the NixOS configuration of this VPS.
#
# The configuration is split into modules under ./modules:
#
#   host.nix      Platform parity with the Hostinger KVM image this VPS boots
#                 from (disk layout, boot loader, cloud-init, guest agent).
#                 Changing anything here can make the machine unbootable.
#   security.nix  Firewall, kernel hardening, SSH brute-force protection,
#                 Nix store hygiene, log retention.
#   docker.nix    The Docker daemon and its hardening options.
#   portainer.nix Portainer CE, run as a systemd-managed container.
#   proxy.nix     Caddy: terminates TLS and reverse proxies each public
#                 hostname listed in the host file.
#   secrets.nix   Wires the per-machine secret files to the services that
#                 need them.
#
# Host-specific values live in hosts/<name>.nix; see hosts/nixos.nix. The
# deployment's domain and contact address come from the environment; see
# lib/env.nix and .env.example.
{
  config,
  lib,
  pkgs,
  modulesPath,
  hostConfig,
  ...
}:
{
  imports = [
    # virtio_scsi / virtio_blk and friends in the initrd so the image boots on
    # Proxmox. (Identical to the Hostinger template.)
    "${modulesPath}/profiles/qemu-guest.nix"

    ./modules/host.nix
    ./modules/security.nix
    ./modules/docker.nix
    ./modules/portainer.nix
    ./modules/proxy.nix
    ./modules/secrets.nix
  ];

  warnings =
    lib.optional (builtins.any (vhost: lib.hasSuffix ".invalid" vhost.name) hostConfig.vhosts) ''
      At least one public hostname is still a placeholder (.invalid).
      Set the real hostnames in hosts/nixos.nix and add a DNS A record for
      each of them, pointing at this machine's public IP address.
    ''
    ++ lib.optional ((hostConfig.domain or "example.com") == "example.com") ''
      The domain is still the placeholder "example.com". Set PUBLIC_DOMAIN in
      .env to the domain this machine serves, and add a DNS A record for each
      of its hostnames, pointing at this machine's public IP address.
    ''
    ++ lib.optional (lib.hasInfix "example.com" hostConfig.acmeEmail) ''
      hostConfig.acmeEmail is still the placeholder "admin@example.com".
      Set ACME_EMAIL in .env to a real contact address.
    ''
    ++ lib.optional ((hostConfig.publicIp or "203.0.113.10") == "203.0.113.10") ''
      hostConfig.publicIp is still the placeholder "203.0.113.10".
      Set PUBLIC_IP in .env to this machine's public IPv4 address, and point
      each of the DNS A records at it.
    '';
}
