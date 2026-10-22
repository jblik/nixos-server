{ config, lib, ... }:
let
  window =
    default:
    lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs [ "start" "end" ] (
          name:
          lib.mkOption (
            {
              type = lib.types.strMatching "([01][0-9]|2[0-3]):[0-5][0-9]";
              description = "${name} of the daily window in server time (HH:MM). Equal times disable it; an earlier end crosses midnight.";
            }
            // lib.optionalAttrs (builtins.hasAttr name default) {
              default = default.${name};
            }
          )
        );
      };
      default = { };
    };
  maintenanceWindowTask =
    extraOptions:
    lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = config.host.maintenance.enable;
            description = "Enable this maintenance task. Defaults to the shared maintenance switch.";
          };
          window = window config.host.maintenance.window;
        }
        // extraOptions;
      };
      default = { };
    };
in
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

    maintenance = {
      enable = lib.mkEnableOption "scheduled maintenance";
      window = window { };
      keepCool = maintenanceWindowTask { };
      qbittorrent = maintenanceWindowTask { };
      tdarr = maintenanceWindowTask { };
      mediaPreviewGenerator = maintenanceWindowTask {
        cpuWorkers = lib.mkOption {
          type = lib.types.ints.between 1 64;
          default = 2;
          description = "Dedicated preview CPU workers during their scheduled window.";
        };
      };
    };

    networking = {
      dnsPort = lib.mkOption {
        type = lib.types.port;
        default = 53;
        readOnly = true;
        description = "Standard DNS resolver port.";
      };
      mdnsPort = lib.mkOption {
        type = lib.types.port;
        default = 5353;
        readOnly = true;
        description = "Standard multicast DNS port.";
      };
      wakeOnLanPort = lib.mkOption {
        type = lib.types.port;
        default = 9;
        readOnly = true;
        description = "Wake-on-LAN UDP port accepted by the firewall.";
      };
      smtpPort = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "SMTP submission port used by Paperless and Alertmanager.";
      };
    };

    media = {
      enable = lib.mkEnableOption "Plex and the *arr stack (modules/services/media)";

      qbittorrent.port = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "qBittorrent web UI port.";
      };
      qbittorrent.vpnPort = lib.mkOption {
        type = lib.types.port;
        default = 51820;
        readOnly = true;
        description = "NordVPN WireGuard endpoint port.";
      };
      sonarr.port = lib.mkOption {
        type = lib.types.port;
        default = 8989;
        description = "Sonarr web UI port.";
      };
      radarr.port = lib.mkOption {
        type = lib.types.port;
        default = 7878;
        description = "Radarr web UI port.";
      };
      bazarr.port = lib.mkOption {
        type = lib.types.port;
        default = 6767;
        description = "Bazarr web UI port.";
      };
      jackett.port = lib.mkOption {
        type = lib.types.port;
        default = 9117;
        description = "Jackett web UI port.";
      };
      flaresolverr.port = lib.mkOption {
        type = lib.types.port;
        default = 8191;
        description = "FlareSolverr API port.";
      };
      tdarr.port = lib.mkOption {
        type = lib.types.port;
        default = 8265;
        description = "Tdarr web UI port.";
      };
      tdarr.serverPort = lib.mkOption {
        type = lib.types.port;
        default = 8266;
        description = "Tdarr server API port.";
      };
      mediaPreviewGenerator = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8280;
          description = "Media preview generator web UI port.";
        };
      };

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

    forgejo = {
      enable = lib.mkEnableOption "the Forgejo git forge (modules/services/forgejo.nix)";
      port = lib.mkOption {
        type = lib.types.port;
        default = 3000;
        description = "Forgejo web UI port.";
      };
      sshPort = lib.mkOption {
        type = lib.types.port;
        default = 2222;
        description = "Forgejo SSH port. Also update the dashboard input URL in flake.nix when changing it.";
      };
    };

    immich.enable = lib.mkEnableOption "the Immich photo library (modules/services/immich.nix)";
    immich.machineLearningPort = lib.mkOption {
      type = lib.types.port;
      default = 3004;
      description = "Immich machine learning API port.";
    };

    home-assistant.enable = lib.mkEnableOption "Home Assistant and its Apple Home bridge (modules/services/home-assistant.nix)";
    home-assistant.port = lib.mkOption {
      type = lib.types.port;
      default = 8123;
      description = "Home Assistant HTTP port.";
    };
    home-assistant.homekitPort = lib.mkOption {
      type = lib.types.port;
      default = 21063;
      description = "Home Assistant HomeKit bridge port.";
    };
    home-assistant.matterPort = lib.mkOption {
      type = lib.types.port;
      default = 5540;
      readOnly = true;
      description = "Standard Matter UDP port.";
    };

    music-assistant = {
      enable = lib.mkEnableOption "Music Assistant and the Sendspin Bluetooth bridge (modules/services/music-assistant.nix)";
      ma-port = lib.mkOption {
        type = lib.types.port;
        default = 8095;
        readOnly = true;
        description = "Music Assistant default web UI port. The NixOS module exposes no listener port setting, so this only records it.";
      };
      sendspin-port = lib.mkOption {
        type = lib.types.port;
        default = 8098;
        description = "Sendspin Bluetooth bridge web UI port.";
      };
      streamPort = lib.mkOption {
        type = lib.types.port;
        default = 8097;
        readOnly = true;
        description = "Music Assistant default stream port; managed through its UI.";
      };
      sendspinServerPort = lib.mkOption {
        type = lib.types.port;
        default = 8927;
        readOnly = true;
        description = "Music Assistant default Sendspin server port; managed through its UI.";
      };
      sendspinBasePort = lib.mkOption {
        type = lib.types.port;
        default = 8928;
        description = "Base listener port for Sendspin Bluetooth bridge players.";
      };
      spotifyPortRange = {
        from = lib.mkOption {
          type = lib.types.port;
          default = 32768;
          readOnly = true;
          description = "Start of the host ephemeral TCP range used by Spotify Connect.";
        };
        to = lib.mkOption {
          type = lib.types.port;
          default = 60999;
          readOnly = true;
          description = "End of the host ephemeral TCP range used by Spotify Connect.";
        };
      };
    };

    paperless.enable = lib.mkEnableOption "the Paperless-ngx document archive (modules/services/paperless.nix)";
    paperless.gotenbergPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "Gotenberg document conversion API port.";
    };

    microbin = {
      enable = lib.mkEnableOption "the MicroBin paste bin (modules/services/microbin.nix)";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8081;
        description = "MicroBin web UI port.";
      };
    };

    dashboard.enable = lib.mkEnableOption "the dashboard on server.steenblik.ch (modules/services/dashboard.nix)";
    dashboard.grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3002;
      description = "Grafana HTTP port.";
    };

    fans.port = lib.mkOption {
      type = lib.types.port;
      default = 11987;
      description = "CoolerControl API and web UI port (modules/hardware/fans/default.nix).";
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
        (modules/hardware/fans/default.nix) and the dashboard (modules/services/dashboard.nix)
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
        description = "Open WebUI port (localhost)";
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
