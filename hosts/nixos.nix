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
  # (PUBLIC_DOMAIN in .env). It identifies the deployment; the public
  # hostnames themselves belong to the application stack.
  domain = env.domain;

  # **No ACME account here.** The certificates for this machine's public
  # hostnames are obtained by the edge — the container in the application
  # stack that holds ports 80 and 443 — and it keeps the account. The edge
  # needs inbound port 80 for the HTTP-01 challenge, so it is the only process
  # on the box that could obtain one.

  # The public IPv4 address of this machine. Every DNS A record for the
  # hostnames the edge serves points here. Comes from the environment
  # (PUBLIC_IP in .env).
  publicIp = env.publicIp;

  # **No hostname list here.** The public hostnames of this machine are the
  # application's, and the edge serves all of them — it is configured in the
  # panel of the application stack, not in this repository. The DNS records
  # those hostnames need are listed in that project's runbook.
  #
  # The box's own services are published on loopback and reached over an SSH
  # tunnel; see modules/portainer.nix.

  # Secret files for this machine.
  #
  # The path is relative to the repository root, so it follows the checkout
  # wherever it lives and never has to be an absolute path. The default is
  # <checkout>/secrets.
  #
  # These are paths only. The contents live on the VPS, not in git. Run
  # scripts/init-secrets.sh to create the directory and the files.
  secrets = {
    dir = env.secretsDir;
  };
}
