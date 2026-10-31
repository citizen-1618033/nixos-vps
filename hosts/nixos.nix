# Host-specific values for this VPS.
#
# Everything in this file is public information (no secrets), so it is safe to
# commit. Secrets do not belong here: they live in root-owned files on the VPS
# itself and are referenced by path from modules/secrets.nix.
#
# One file per machine. The file name is the flake output name:
#   hosts/nixos.nix  ->  nixosConfigurations.nixos
#                       scripts/rebuild.sh            (or: nixos-rebuild
#                                                    switch --flake .#nixos)
#
# An optional hosts/nixos.extra.nix next to this file is imported as an extra
# NixOS module, for per-machine overrides that do not belong in the shared
# modules.

let
  # Deployment values, read from the environment. See lib/env.nix and
  # .env.example.
  env = import ../lib/env.nix;
in
{
  # The hostname of the machine. The Hostinger template ships with "nixos".
  hostname = "nixos";

  # The base domain this machine serves. It comes from the environment
  # (PUBLIC_DOMAIN in .env), and the public hostnames below are derived from
  # it.
  domain = env.domain;

  # Contact address registered with the ACME certificate authority
  # (Let's Encrypt). Used for expiry notices and abuse reports. Comes from the
  # environment (ACME_EMAIL in .env).
  acmeEmail = env.acmeEmail;

  # The public IPv4 address of this machine. Every hostname listed in `vhosts`
  # needs a DNS A record pointing here. Comes from the environment
  # (PUBLIC_IP in .env).
  publicIp = env.publicIp;

  # Public hostnames served by this machine.
  #
  # Each entry becomes one Caddy site block with its own certificate:
  #   name     the public hostname. It needs a DNS A record pointing at this
  #            machine's public IP, otherwise the ACME HTTP-01 challenge
  #            cannot be completed and no certificate is issued.
  #   upstream what to reverse proxy to:
  #            "portainer"  -> the Portainer UI on 127.0.0.1:9443
  #            "<host>:<port>" -> a container that publishes that port on
  #                            loopback, e.g. "127.0.0.1:3000"
  #
  # Publishing a container port on a routable address bypasses the NixOS
  # firewall, because Docker installs its own DNAT rules ahead of it. So an
  # application's port must be published on 127.0.0.1 and reached through a
  # reverse proxy like this.
  vhosts = [
    {
      name = "portainer.app.${env.domain}";
      upstream = "portainer";
    }

    # Reserved for the application zone. Point this at the loopback port
    # that your application container publishes, for example 127.0.0.1:3000.
    # It is commented out until that container exists: an entry pointing at a
    # port with nothing behind it answers with a 502.
    # {
    #   name = "app.${env.domain}";
    #   upstream = "127.0.0.1:3000";
    # },
  ];

  # Secret files for this machine.
  #
  # These are paths only. The contents live on the VPS, not in git. Run
  # scripts/init-secrets.sh to create the directory and the files.
  secrets = {
    dir = "/etc/nix-vps";
  };
}
