# Platform parity with the Hostinger KVM template this VPS was created from.
#
# The VPS image was built with nixpkgs' `make-disk-image` (not `nixos-infect`),
# so the running system already has a specific disk layout, boot loader and
# provisioning setup. Everything in this file describes that layout, and it
# MUST keep describing it: if it drifts, `nixos-rebuild` will produce a system
# that does not match the disk it is running on.
#
# Original source: the template's /etc/nixos/configuration.nix on the VPS.
{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
{
  networking.hostName = hostConfig.hostname;

  # --- Disk and boot -------------------------------------------------------
  # BIOS/SeaBIOS GRUB on the single legacy (MBR) disk. `device` is the VPS
  # disk (scsi0), used when the customer runs nixos-rebuild.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.efiSupport = false;
  boot.loader.timeout = 1;

  # Root is the single labelled partition make-disk-image creates; it is grown
  # to the provisioned disk size on first boot (Hostinger resizes the disk).
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  boot.growPartition = true;

  # Serial console for the Proxmox serial0 + memory hotplug.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
    "earlyprintk=ttyS0,115200"
    "consoleblank=0"
    "memhp_default_state=online"
  ];

  # Loaded explicitly rather than relying on udev to autoload them, so that
  # `security.lockKernelModules` (see modules/security.nix) cannot leave the
  # machine without disk or network after boot. All of these exist in the
  # NixOS kernel: the first four are in the `qemu-guest` profile's
  # `boot.initrd.availableKernelModules`, and `virtio_rng` is in that profile's
  # `boot.initrd.kernelModules` (loaded rather than merely available, so it is
  # not in the `available` set). The kernel ships it as `virtio-rng.ko`;
  # modprobe normalises the `-`/`_` difference, so `virtio_rng` resolves.
  boot.kernelModules = [
    "virtio_blk"
    "virtio_net"
    "virtio_pci"
    "virtio_scsi"
    "virtio_rng"
  ];

  # --- Proxmox / Hostinger integration -------------------------------------
  # QEMU guest agent: how Proxmox/hVPS talk to the VM.
  services.qemuGuest.enable = true;

  # Provisioning via the Proxmox cloud-init drive. Proxmox exposes config
  # through the NoCloud datasource; pin it (NixOS ships no default).
  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;
  services.cloud-init.settings.datasource_list = [
    "NoCloud"
    "ConfigDrive"
  ];

  # The keys-to-console module's helper (write-ssh-key-fingerprints) is not
  # shipped in NixOS's cloud-init package, so it errors and downgrades
  # cloud-init to "degraded done" (exit 2). It only prints host-key
  # fingerprints to the console, so disable it for a clean exit 0.
  services.cloud-init.settings.ssh.emit_keys_to_console = false;

  # cloud-init owns IP assignment, so DHCP must be off (otherwise it races
  # cloud-init).
  #
  # Note: this makes cloud-init the single point of failure for networking.
  # The config defines no `networking.interfaces`, so NixOS generates no
  # systemd-networkd units of its own; the address comes from the provider's
  # cloud-init drive. If that drive carries no network-config, the machine
  # comes up without an address and systemd-networkd-wait-online stalls for
  # 120s before the boot continues. docs/DEPLOY.md §6 has a check for this.
  networking.useDHCP = lib.mkForce false;

  # hVPS drives provisioning by running bare-name commands (sh, cloud-init,
  # and similar) through the guest agent, which resolves them on the
  # *agent's* PATH. NixOS gives services a minimal PATH and keeps `sh` only in
  # /bin, so point the agent at the full system environment.
  environment.systemPackages = with pkgs; [
    cloud-init
    dnsutils # dig, nslookup, host
    nettools # ifconfig, netstat, route (net-tools parity)
    curl
    wget
    nano
  ];

  systemd.services.qemu-guest-agent.environment.PATH =
    lib.mkForce "/run/wrappers/bin:/run/current-system/sw/bin:/bin";

  # --- SSH -----------------------------------------------------------------
  services.openssh.enable = true;

  # The provider's provisioning workflow logs in as root during handover, so
  # root login has to stay enabled until the machine has been handed over.
  # See docs/DEPLOY.md for the lock-down procedure to run once handover is
  # finished.
  services.openssh.settings.PermitRootLogin = lib.mkDefault "yes";

  # --- NixOS release --------------------------------------------------------
  # Data-format version, not a package version. Do not bump casually.
  system.stateVersion = "26.05";
}
