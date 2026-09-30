{ ... }:
# Per-host entry point. Imports the machine's generated hardware config and
# sets the site-specific knobs declared in modules/options.nix.
{
  imports = [
    ./hardware-configuration.nix
  ];

  host = {
    hostname = "nixos-server";
    timezone = "Europe/Brussels";

    cpuVendor = "amd";

    lanCidr = "192.168.1.0/24";

    media.enable = true;
    forgejo.enable = true;

    storage = {
      # Fast tier: ZFS mirror on the SanDisk + PEAQ SATA SSDs.
      fastPool = "fast";
      hostId = "c60968bd";

      # Bulk tier. disk1 is the 10 TB, holding data with no parity; it becomes
      # the parity disk at the end of the migration (docs/MIGRATION.md).
      dataDisks = {
        d1 = "/mnt/disk1";
      };
      parityFiles = [
        # "/mnt/parity1/snapraid.parity"   # must be >= the largest data disk
      ];

      # spinDownSeconds = 900;   # unraid-style idle spin-down (HDDs only)
    };
  };

  fileSystems."/mnt/disk1" = {
    device = "/dev/disk/by-id/ata-ST10000NE0008-2PL103_ZS5072G6-part1";
    fsType = "xfs";
    options = [ "noatime" ];
  };

  # mountpoint=legacy datasets, so the mounts are ordered before the services.
  fileSystems."/var/lib/forgejo" = {
    device = "fast/forgejo";
    fsType = "zfs";
  };

  # Do not change after install unless you know what you're doing.
  system.stateVersion = "26.05";
}
