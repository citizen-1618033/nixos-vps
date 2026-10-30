# Docker Engine on NixOS.
#
# The daemon is configured through `virtualisation.docker.daemon.settings`,
# which nixpkgs serialises into a read-only daemon.json in the Nix store and
# passes to dockerd with `--config-file`. Do not set `ExecStart` yourself:
# nixpkgs already does that, and overriding it breaks the daemon.json wiring.
#
# Docker's own security notes: https://docs.docker.com/engine/security/
{
  config,
  lib,
  pkgs,
  ...
}:
{
  virtualisation.docker = {
    enable = true;

    # Set the storage driver explicitly. nixpkgs recommends this because
    # Docker's own default varies between releases. Changing it later makes
    # existing images and containers inaccessible, so decide now.
    storageDriver = "overlay2";

    # nixpkgs defaults the daemon to the `journald` log driver (upstream
    # defaults to `json-file`). With journald, container logs live in the
    # systemd journal and are bounded by `services.journald.extraConfig`
    # instead of growing unbounded json files on the root filesystem.
    logDriver = "journald";

    daemon.settings = {
      # Keep containers running across a dockerd restart (daemon upgrade,
      # configuration change, host reboot of the daemon unit). Incompatible
      # with Docker Swarm, which this host does not use.
      #
      # Note: nixpkgs leaves this unset (i.e. upstream's `false`) for
      # stateVersion >= 24.11, so it has to be requested explicitly.
      "live-restore" = true;

      # Containers on the *default* bridge network cannot talk to each other.
      # User-defined networks, which is what Portainer stacks and compose
      # projects create, are unaffected.
      "icc" = false;

      # Containers cannot gain privileges through setuid or file-capability
      # binaries. This is the single most useful daemon-wide default for a
      # host that runs third-party application images.
      #
      # Per-container opt-out, when an image genuinely needs it:
      #   docker run --security-opt no-new-privileges=false ...
      # or, from Portainer: "Security options" -> "no-new-privileges:false".
      "no-new-privileges" = true;

      # Raise the open-file limit for containers. The Docker default of 1024
      # is too low for anything that keeps many files open.
      "default-ulimits" = {
        nofile = {
          Name = "nofile";
          Soft = 64000;
          Hard = 64000;
        };
      };
    };

    # Reclaim disk space weekly: stopped containers, dangling images, unused
    # networks and build cache.
    #
    # Volumes are deliberately NOT pruned. `portainer_data` and any
    # application volumes are named volumes and survive `docker system prune`
    # anyway, but pruning anonymous volumes would silently destroy data for
    # applications that declare their volumes anonymously.
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ ];
    };
  };

  # --------------------------------------------------------------------------
  # The `docker` group is root-equivalent.
  #
  # From Docker's own documentation:
  #   "The `docker` group grants root-level privileges to the user."
  #   (https://docs.docker.com/engine/install/linux-postinstall/)
  #
  # nixpkgs creates the socket as root:docker with mode 0660, so every member
  # of the `docker` group can talk to the daemon and therefore mount the host
  # filesystem into a container. The `docker` group is deliberately left
  # empty here:
  #
  #   * Application management happens through Portainer, which is the
  #     intended interface.
  #   * The `docker` CLI is still available to root through sudo.
  #
  # To get CLI access as a non-root user, add it knowingly:
  #   users.users.<name>.extraGroups = [ "docker" ];
  # --------------------------------------------------------------------------
}
