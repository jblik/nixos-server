{ lib, ... }:
# Per-host entry point. Imports the machine's generated hardware config and
# sets the site-specific knobs declared in modules/options.nix.
let
  # SnapRAID name -> disk, which is also mounted at /mnt/<name>.
  hdds = {
    d1 = {
      name = "disk1";
      model = "ST10000NE0008-2PL103";
      serial = "ZS5072G6";
    };
    d2 = {
      name = "disk2";
      model = "ST4000VN008-2DR166";
      serial = "ZM40T6NK";
    };
  };

  mountOf = hdd: "/mnt/${hdd.name}";
in
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
        snapshot = {
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
          immich = "/var/lib/immich";
        };
        # Regeneratable from the originals.
        noSnapshot = {
          immich-thumbs = "/var/lib/immich/thumbs";
          immich-encoded-video = "/var/lib/immich/encoded-video";
        };
      };

      dataDisks = lib.mapAttrs (_: mountOf) hdds;

      parityFiles = [
        # "/mnt/parity1/snapraid.parity"
      ];

      spinDownSeconds = 900; # idle spin-down (HDDs only)
    };

    sensors = {
      # temp2 is Tdie; temp1 is Tctl, which carries a +10 °C offset on the 2700X.
      cpu = {
        name = "CPU";
        device = "AMD Ryzen 7 2700X Eight-Core Processor";
        sensor = "temp2";
        kind = "Cpu";
      };
      gpu = {
        name = "GPU";
        device = "NVIDIA GeForce RTX 3060";
        sensor = "GPU Temp";
        kind = "Gpu";
      };
      chipset = {
        name = "Chipset";
        device = "nct6798";
        sensor = "temp9";
        kind = "Chipset";
      };
      motherboard = {
        name = "Motherboard";
        device = "nct6798";
        sensor = "temp1";
        kind = "Board";
      };
      sandisk = {
        name = "SSD (SanDisk)";
        device = "SanDisk SSD PLUS";
        sensor = "temp1";
        kind = "Ssd";
      };
      peaq = {
        name = "SSD (PEAQ)";
        device = "PEAQ    SSD_256G";
        sensor = "temp1";
        kind = "Ssd";
      };
      nvme = {
        name = "NVMe";
        device = "nvme";
        sensor = "temp1";
        kind = "Nvme";
      };
    }
    // lib.mapAttrs' (
      _: hdd:
      lib.nameValuePair hdd.name {
        inherit (hdd) name;
        device = builtins.substring 0 16 hdd.model;
        sensor = "temp1";
        kind = "Hdd";
      }
    ) hdds;
  };

  fileSystems = lib.mapAttrs' (
    _: hdd:
    lib.nameValuePair (mountOf hdd) {
      device = "/dev/disk/by-id/ata-${hdd.model}_${hdd.serial}-part1";
      fsType = "xfs";
      options = [ "noatime" ];
    }
  ) hdds;

  # Do not change after install unless you know what you're doing.
  system.stateVersion = "26.05";
}
