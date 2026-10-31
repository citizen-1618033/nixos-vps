# Portainer CE, run as a systemd-managed container on the Docker backend.
#
# Why the Docker backend and not Podman:
#
#   * Portainer's official documentation supports Docker standalone, Docker
#     Swarm, Podman and Kubernetes on Linux. There is no documented "binary
#     on systemd" install. The Docker path is the canonical, tested one.
#     (https://docs.portainer.io/start/install-ce/server/docker/linux)
#   * Portainer's Podman path requires `--privileged` and Portainer itself
#     states that Podman support "is limited to configurations where that
#     Docker-compatible API behaves consistently".
#
# Why the container is published on loopback only:
#
#   * "Publishing a port bypasses the NixOS firewall." Docker installs its
#     own DNAT rules ahead of the NixOS input chain, so a port published on
#     0.0.0.0 is reachable no matter what `networking.firewall` says.
#     (nixos/modules/virtualisation/oci-containers.nix)
#   * Binding to 127.0.0.1 means the NixOS firewall still decides who can
#     reach Portainer, because the only way in is Caddy on 443.
#     (see modules/proxy.nix)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.portainer;
in
{
  options.portainer = {
    # Enabled by default; set `portainer.enable = false` to leave it out.
    enable = lib.mkEnableOption "Portainer CE, managed by systemd on the Docker backend" // {
      default = true;
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/portainer/portainer-ce@sha256:3609c307943bca8e5c492f69ddd6965df177208b50678a4cff28391c8dd4e96e";
      description = ''
        Portainer CE image, pinned by digest so that a rebuild always produces
        the same container.

        The default is Portainer CE 2.45.3 (LTS). Re-derive the digest for a
        newer release with:

          docker buildx imagetools inspect portainer/portainer-ce:<version>

        or

          curl -sSI -H "Authorization: Bearer $(curl -sS \
            "https://auth.docker.io/token?service=registry.docker.io&scope=repository:portainer/portainer-ce:pull" \
            | jq -r .token)" \
            -H "Accept: application/vnd.oci.image.index.v1+json" \
            https://registry-1.docker.io/v2/portainer/portainer-ce/manifests/<version> \
            | grep -i docker-content-digest
      '';
    };

    publishedAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Host address the Portainer UI/API port is published on.

        Keep this on loopback. Publishing on a routable address bypasses the
        NixOS firewall entirely, because Docker installs its own DNAT rules
        ahead of it.
      '';
    };

    publishedPort = lib.mkOption {
      type = lib.types.port;
      default = 9443;
      description = "Host port the Portainer UI/API is published on.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers = {
      # The Docker backend. modules/docker.nix sets
      # `virtualisation.docker.enable = true`; nixpkgs then generates a
      # systemd unit and orders it after docker.service and docker.socket.
      backend = "docker";

      containers.portainer = {
        image = cfg.image;

        # Loopback only. See the note at the top of this file.
        ports = [ "${cfg.publishedAddress}:${toString cfg.publishedPort}:9443" ];

        volumes = [
          # The Docker API socket. This is how Portainer manages containers,
          # and it is also why Portainer is root-equivalent on this host: it
          # can start a container with the host filesystem mounted. Do not
          # expose the socket itself.
          "/run/docker.sock:/var/run/docker.sock"

          # Portainer's own database. `portainer_data` is the volume name
          # Portainer's official install uses.
          "portainer_data:/data"
        ];

        # Keep the container in `docker ps` between restarts instead of using
        # `--rm`.
        autoRemoveOnStop = false;

        autoStart = true;

        # The image is pinned by digest, so "pull only if absent" is exactly
        # what we want: the first boot fetches it, later boots reuse it.
        pull = "missing";

        # journald, so container logs are bounded by the journal size cap in
        # modules/security.nix rather than growing json files on disk.
        log-driver = "journald";
      };
    };

    # The Portainer container needs the Docker socket to exist. nixpkgs
    # already orders the unit after docker.socket for the Docker backend, but
    # it does not require it, so state that dependency explicitly.
    systemd.services."docker-portainer".requires = [ "docker.socket" ];
  };
}
