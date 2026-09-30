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

    storage = {
      # Fast tier (sdb + sdc), not created yet:
      #   zpool create -o ashift=12 -O compression=zstd -O atime=off fast \
      #     mirror /dev/disk/by-id/<ssd-a> /dev/disk/by-id/<ssd-b>
      # fastPool = "fast";
      # hostId = "xxxxxxxx";   # head -c 8 /etc/machine-id

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

  # Do not change after install unless you know what you're doing.
  system.stateVersion = "26.05";
}
