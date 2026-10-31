{
  description = "Security-hardened NixOS 26.05 VPS with Docker and Portainer CE behind a TLS reverse proxy";

  inputs = {
    # Pinned to the stable 26.05 release branch. The exact revision is
    # recorded in flake.lock, so the configuration is reproducible until you
    # explicitly run `nix flake update`.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = nixpkgs.lib;

      # Every hosts/<name>.nix file describes one machine. The file name
      # becomes the flake output name:
      #   hosts/nixos.nix -> nixosConfigurations.nixos
      #                       scripts/rebuild.sh   (or: nixos-rebuild
      #                                                 switch --flake .#nixos)
      #
      # An optional hosts/<name>.extra.nix next to it is imported as an extra
      # NixOS module, for instance-specific overrides.
      hostDir = ./hosts;

      hostFileNames = builtins.filter (
        name:
        let
          entry = builtins.getAttr name (builtins.readDir hostDir);
          # Nix >= 2.31 returns the entry type as a plain string ("regular");
          # older Nix returns an attrset with a `type` field.
          entryType = if builtins.isAttrs entry then entry.type else entry;
          isFile = entryType == "regular" || entryType == "file";
        in
        # `hosts/<name>.extra.nix` is a module fragment, not a machine, so it
        # must not be registered as one: it has none of the fields
        # hostConfig is expected to have, and evaluating it as a host fails.
        isFile && lib.hasSuffix ".nix" name && !(lib.hasSuffix ".extra.nix" name)
      ) (builtins.attrNames (builtins.readDir hostDir));

      mkHost =
        fileName:
        let
          # `hostDir` is a store path, so this is an absolute path and `import`
          # resolves it correctly rather than relative to the working
          # directory.
          hostPath = toString hostDir + "/";
          hostName = lib.removeSuffix ".nix" (builtins.baseNameOf fileName);
          hostConfig = import (hostPath + fileName);
          extraFile = hostPath + hostName + ".extra.nix";
        in
        {
          name = hostName;
          value = lib.nixosSystem {
            inherit system;
            specialArgs = { inherit hostConfig; };
            modules = [ ./configuration.nix ] ++ lib.optional (builtins.pathExists extraFile) extraFile;
          };
        };
    in
    {
      nixosConfigurations = builtins.listToAttrs (map mkHost hostFileNames);

      # `nix build .#nixos` builds one host's system closure.
      #
      # Note: a plain build is a *pure* evaluation, so it cannot see the
      # environment and every deployment value falls back to its placeholder
      # (domain "example.com", ACME email "admin@example.com"). The result is
      # a valid system, but with a Caddyfile for the wrong hostname. Use
      # scripts/rebuild.sh, which passes --impure, to build the real thing.
      packages.${system} = builtins.mapAttrs (
        _name: host: host.config.system.build.toplevel
      ) self.nixosConfigurations;

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.nixfmt ];
      };
    };
}
