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
    immich.enable = true;
    paperless.enable = true;
    microbin.enable = true;
    dashboard.enable = true;

    storage = {
      # Fast tier: ZFS mirror on the SanDisk + PEAQ SATA SSDs.
      fastPool = "fast";
      hostId = "c60968bd";
      fastDatasets = {
        forgejo = "/var/lib/forgejo";
        plex = "/var/lib/plex";
        sonarr = "/var/lib/sonarr";
        radarr = "/var/lib/radarr";
        bazarr = "/var/lib/bazarr";
        jackett = "/var/lib/jackett";
        qbittorrent = "/var/lib/qBittorrent";
        tdarr = "/var/lib/tdarr";
        cleanuparr = "/var/lib/cleanuparr";
        pulsarr = "/var/lib/pulsarr";
        maintainerr = "/var/lib/maintainerr";
        postgresql = "/var/lib/postgresql";
        paperless = "/var/lib/paperless";
        microbin = "/var/lib/private/microbin"; # DynamicUser: /var/lib/microbin is a symlink
        immich-thumbs = "/data/photos/thumbs";
        immich-encoded-video = "/data/photos/encoded-video";
        immich-backups = "/data/photos/backups";
      };

      dataDisks = {
        d1 = "/mnt/disk1";
        d2 = "/mnt/disk2";
      };

      parityFiles = [
        # "/mnt/parity1/snapraid.parity"
      ];

      spinDownSeconds = 900; # idle spin-down (HDDs only)
    };
  };

  fileSystems = {
    "/mnt/disk1" = {
      device = "/dev/disk/by-id/ata-ST10000NE0008-2PL103_ZS5072G6-part1";
      fsType = "xfs";
      options = [ "noatime" ];
    };
    "/mnt/disk2" = {
      device = "/dev/disk/by-id/ata-ST4000VN008-2DR166_ZM40T6NK-part1";
      fsType = "xfs";
      options = [ "noatime" ];
    };
  };

  # Do not change after install unless you know what you're doing.
  system.stateVersion = "26.05";
}
