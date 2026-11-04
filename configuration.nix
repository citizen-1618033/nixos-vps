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
#   secrets.nix   Wires the per-machine secret files to the services that
#                 need them.
#
# There is no proxy here, and that is deliberate: **the box's front door is
# the edge container of the application stack**, which holds the public ports
# and terminates TLS for every public hostname on the machine. What this
# configuration owns is the services the box itself runs, and they are
# published on loopback and reached over an SSH tunnel.
#
# Host-specific values live in hosts/<name>.nix; see hosts/nixos.nix. The
# deployment's domain and public address come from the environment; see
# lib/env.nix and .env.example.
{
  config,
  lib,
  pkgs,
  modulesPath,
  hostConfig,
  ...
}:
let
  env = import ./lib/env.nix;
in
{
  imports = [
    # virtio_scsi / virtio_blk and friends in the initrd so the image boots on
    # Proxmox. (Identical to the Hostinger template.)
    "${modulesPath}/profiles/qemu-guest.nix"

    ./modules/host.nix
    ./modules/security.nix
    ./modules/docker.nix
    ./modules/portainer.nix
    ./modules/secrets.nix
  ];

  warnings =
    lib.optional ((hostConfig.domain or "example.com") == "example.com") ''
      The domain is still the placeholder "example.com". Set PUBLIC_DOMAIN in
      .env to the domain this machine serves, and add a DNS A record for each
      of the hostnames the application stack serves, pointing at this machine's
      public IP address.
    ''
    ++ lib.optional ((hostConfig.publicIp or "203.0.113.10") == "203.0.113.10") ''
      hostConfig.publicIp is still the placeholder "203.0.113.10".
      Set PUBLIC_IP in .env to this machine's public IPv4 address, and point
      each of the DNS A records at it.
    ''
    ++ lib.optional (!env.repoRootIsCheckout) ''
      The checkout root is unknown, so the secret files are looked for in the
      flake's own source directory, where they are not. Build with
      scripts/rebuild.sh, which tells the configuration where the checkout
      is.
    '';
}
