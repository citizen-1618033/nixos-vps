# Secret handling.
#
# The convention: every machine keeps its secret files in one directory
# (hostConfig.secrets.dir, default /etc/nix-vps), mode 0700 root:root. They
# are never in git and never in the Nix store -- Nix only ever holds the
# *path* to a file, so no secret is ever readable by everyone on the box.
#
# scripts/init-secrets.sh creates the directory and the files. Run it once per
# machine, before the first `nixos-rebuild switch`.
#
# Application secrets are deliberately NOT handled here: those belong to the
# containers, and Portainer manages them.
{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  # A host file without a `secrets` block still works.
  secrets =
    hostConfig.secrets or {
      dir = "/etc/nix-vps";
    };

  dir = secrets.dir;
in
{
  # The Portainer container reads its environment from an .env file, so the
  # setup token never appears on the docker command line, in the systemd unit
  # file, or in the Nix store.
  #
  # Portainer reads PORTAINER_SETUP_TOKEN from its environment (kingpin's
  # .Envar()), so it does not have to be scraped out of the container logs.
  virtualisation.oci-containers.containers.portainer.environmentFiles =
    lib.mkIf config.portainer.enable
      [ "${dir}/portainer.env" ];

  # Caddy's environment, for ACME EAB credentials and similar. The leading
  # "-" makes the file optional: systemd ignores it when it does not exist.
  #
  # This is set on the unit directly rather than through
  # `services.caddy.environmentFile`, because that option takes an absolute
  # path and cannot carry the "-" prefix.
  systemd.services.caddy.serviceConfig.EnvironmentFile = "-${dir}/caddy.env";
}
