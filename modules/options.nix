{ lib, ... }:
{
  options.host = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "nixos-server";
      description = "System hostname.";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Brussels";
      description = "System timezone.";
    };

    cpuVendor = lib.mkOption {
      type = lib.types.enum [
        "amd"
        "intel"
      ];
      default = "amd";
      description = ''
        CPU vendor. Drives which microcode updates are loaded.
      '';
    };

    lanCidr = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.0/24";
      description = ''
        LAN subnet allowed to reach the web UIs and APIs. Tighten this to
        your actual subnet (e.g. "192.168.1.0/24").
      '';
    };

    media = {
      enable = lib.mkEnableOption "Plex, the *arr stack and Tdarr (modules/services/media)";

      plex = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 32400;
          readOnly = true;
          description = "Plex web UI port. The NixOS module hardcodes it, so this only records it.";
        };
      };
      cleanuparr = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 11011;
          description = "Cleanuparr web UI port.";
        };
      };
      pulsarr = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 3003;
          description = "Pulsarr web UI port.";
        };
      };
      maintainerr = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 6246;
          description = "Maintainerr web UI port.";
        };
      };
    };

    forgejo.enable = lib.mkEnableOption "the Forgejo git forge (modules/services/forgejo.nix)";

    immich.enable = lib.mkEnableOption "the Immich photo library (modules/services/immich.nix)";

    paperless.enable = lib.mkEnableOption "the Paperless-ngx document archive (modules/services/paperless.nix)";

    microbin = {
      enable = lib.mkEnableOption "the MicroBin paste bin (modules/services/microbin.nix)";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = "MicroBin web UI port.";
      };
    };

    dashboard.enable = lib.mkEnableOption "the dashboard on server.steenblik.ch (modules/services/dashboard.nix)";

    fans.port = lib.mkOption {
      type = lib.types.port;
      default = 11987;
      description = "CoolerControl API and web UI port (modules/hardware/fans.nix).";
    };

    sensors = lib.mkOption {
      default = { };
      example = {
        cpu = {
          name = "CPU";
          device = "AMD Ryzen 7 2700X Eight-Core Processor";
          sensor = "temp2";
          kind = "Cpu";
        };
      };
      description = ''
        Temperature sensors as CoolerControl reports them. The fan curves
        (modules/hardware/fans.nix) and the dashboard (modules/services/dashboard.nix)
        both read them.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = name;
                description = "Label on the dashboard and in CoolerControl profile names.";
              };

              device = lib.mkOption {
                type = lib.types.str;
                description = "CoolerControl device name; drivetemp names a disk by the first 16 characters of its model.";
              };

              sensor = lib.mkOption {
                type = lib.types.str;
                description = "CoolerControl sensor key on that device, e.g. `temp1`.";
              };

              kind = lib.mkOption {
                type = lib.types.enum [
                  "Cpu"
                  "Gpu"
                  "Board"
                  "Chipset"
                  "Hdd"
                  "Ssd"
                  "Nvme"
                ];
                description = ''
                  What the sensor measures, which sets when the dashboard calls it warm
                  or hot. An `Hdd` reading 0 °C is spun down.
                '';
              };
            };
          }
        )
      );
    };

    ai = {
      enable = lib.mkEnableOption "Ollama and Open WebUI on ai.steenblik.ch (modules/services/ai.nix)";

      models = lib.mkOption {
        description = ''
          Ollama models (<https://ollama.com/library>), pulled on deploy; one that is
          dropped from here is deleted. Any name besides `chat` and `embedding` is only
          pulled, for clients that ask for it by name.
        '';
        example = {
          chat = "qwen3:8b";
          embedding = "embeddinggemma";
          code = "qwen3-coder:30b";
        };
        type = lib.types.submodule {
          freeformType = lib.types.attrsOf lib.types.str;
          options = {
            chat = lib.mkOption {
              type = lib.types.str;
              description = "Open WebUI's default and title model, and Paperless' suggestions and chat.";
            };
            embedding = lib.mkOption {
              type = lib.types.str;
              description = "Embeddings for Open WebUI's and Paperless' document search.";
            };
          };
        };
      };

      apiPort = lib.mkOption {
        type = lib.types.port;
        default = 11434;
        description = "Ollama API port (localhost); public as https://ai.steenblik.ch/v1.";
      };
      openWebuiPort = lib.mkOption {
        type = lib.types.port;
        default = 8082;
        description = "Open WebUI port (localhost). Its default 8080 is qBittorrent's.";
      };
    };

    storage = {
      fastPool = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "fast";
        description = ''
          Name of the ZFS pool used for the fast tier. `null` disables all ZFS
          handling, so the bulk array can be used on its own.

          Create the pool once, by hand, before enabling this:
            zpool create -o ashift=12 -O compression=zstd -O atime=off \
              -O xattr=sa -O acltype=posixacl -O mountpoint=none fast \
              mirror /dev/disk/by-id/<ssd-a> /dev/disk/by-id/<ssd-b>
        '';
      };

      fastDatasets = {
        snapshot = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            forgejo = "/var/lib/forgejo";
          };
          description = ''
            Datasets on the fast pool, as dataset name -> mountpoint, snapshotted by
            sanoid. Each is mounted as `<fastPool>/<name>`; create it first with
            `zfs create -o mountpoint=legacy <fastPool>/<name>` and copy the data over.
          '';
        };

        noSnapshot = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            immich-thumbs = "/data/photos/thumbs";
          };
          description = ''
            Like `snapshot`, but sanoid never snapshots them. For data that can be
            regenerated, where snapshots would only pin every replaced file.
          '';
        };
      };

      hostId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "deadbeef";
        description = ''
          8 hex digits, required by ZFS to detect pools imported by another
          system. Generate with `head -c 8 /etc/machine-id`. Must be set
          whenever `fastPool` is set.
        '';
      };

      bulkMount = lib.mkOption {
        type = lib.types.str;
        default = "/data";
        description = ''
          Mountpoint of the mergerfs union that services see as one filesystem.
          Keep downloads and the media library both under here, or hardlinks
          between them break and every import becomes a full copy.

          `/data` is what Sonarr and Radarr saw inside their unraid containers,
          so their root folders and download paths stay valid if that appdata
          is ever imported.
        '';
      };

      scratchDir = lib.mkOption {
        type = lib.types.str;
        default = "/scratch";
        description = ''
          Fast-storage directory for churning, disposable media files: in-progress
          downloads (`incomplete/`) and the Tdarr transcode cache (`transcode/`).
          It sits on the NVMe root until the fast pool exists; later a ZFS dataset
          can be mounted here without the apps noticing.

          Completed downloads still land in `bulkMount`, so imports stay hardlinks.
        '';
      };

      dataDisks = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          d1 = "/mnt/disk1";
          d2 = "/mnt/disk2";
          d3 = "/mnt/disk3";
        };
        description = ''
          Bulk-tier data disks, as SnapRAID name -> mountpoint. Each is its own
          XFS filesystem (mount them in hardware-configuration.nix or a host
          module, by-id, with `noatime`). Empty disables the bulk tier entirely.
        '';
      };

      parityFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "/mnt/parity1/snapraid.parity" ];
        description = ''
          SnapRAID parity files, one per parity disk. A parity disk must be at
          least as large as the largest data disk. Two parity files are worth it
          once the array passes roughly six data disks.
        '';
      };

      contentFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          SnapRAID content (file listing) files. Left empty, one is derived per
          data disk, which satisfies SnapRAID's "at least parity + 1, on
          different disks" requirement.
        '';
      };

      exclude = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "*.unrecoverable"
          "/tmp/"
          "/lost+found/"
          "*.!sync"
          ".AppleDouble"
          "._AppleDouble"
          ".DS_Store"
          "/incomplete/"
          "/transcode/"
        ];
        description = ''
          Paths excluded from parity. Churning, reproducible data (in-progress
          downloads, transcode scratch) only makes syncs slower.
        '';
      };

      syncInterval = lib.mkOption {
        type = lib.types.str;
        default = "02:00";
        description = "systemd calendar spec for `snapraid sync`.";
      };

      scrubInterval = lib.mkOption {
        type = lib.types.str;
        default = "Mon *-*-* 03:00:00";
        description = "systemd calendar spec for `snapraid scrub`.";
      };

      mergerfsOptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "cache.files=partial"
          "dropcacheonclose=true"
          "category.create=mfs" # new files -> disk with most free space
          "minfreespace=50G"
          "moveonenospc=true"
          "use_ino" # stable inodes across the union: hardlinks work
          "allow_other"
          "fsname=mergerfs"
        ];
        description = ''
          mergerfs mount options. Switch `category.create` to `epmfs` to keep a
          whole directory tree (e.g. one show) on a single disk, so playback
          spins up fewer drives.
        '';
      };

      spinDownSeconds = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 900;
        description = ''
          Idle seconds before bulk-tier disks are spun down, via hd-idle.
          `null` disables it. Do not set this on SSDs.
        '';
      };
    };
  };
}
