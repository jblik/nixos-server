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
      enable = lib.mkEnableOption "the local LLM backend and Open WebUI (modules/services/ai.nix)";

      backend = lib.mkOption {
        type = lib.types.enum [
          "ollama"
          "llama-swap"
        ];
        default = "llama-swap";
        description = ''
          Which local LLM server backend to run. Both expose the same
          OpenAI-compatible API on `ai.apiPort`, so clients (Open WebUI and
          anything else on the LAN) are unaffected by the choice.

          - "llama-swap": upstream llama.cpp behind llama-swap, which starts a
            llama-server per model on demand and unloads it after its TTL.
            Explicit control over -ngl / context / KV-cache quantisation, which
            matters because this GPU is shared with Immich ML and NVENC.
          - "ollama": simpler, model registry, but its VRAM heuristic is opaque
            and it tracks a vendored llama.cpp fork.
        '';
      };

      modelsDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/models";
        description = ''
          Directory holding GGUF weights for the llama-swap backend. Put this on
          the fast (SSD) tier — models are memory-mapped and read constantly.
        '';
      };

      models = lib.mkOption {
        default = { };
        description = ''
          Models served by the llama-swap backend. Each entry becomes a
          `llama-server` instance that llama-swap starts on demand and stops
          again after `ttl` seconds idle, so the GPU is only held while a model
          is actually being used — which matters on a card shared with Immich ML
          and NVENC.

          Ignored when `backend = "ollama"` (Ollama uses its own registry).
        '';
        example = {
          "qwen3-8b" = {
            file = "Qwen3-8B-Q4_K_M.gguf";
            contextSize = 16384;
          };
        };
        type = lib.types.attrsOf (
          lib.types.submodule (
            { name, ... }:
            {
              options = {
                file = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    GGUF filename, relative to `host.ai.modelsDir`, or an
                    absolute path.
                  '';
                };

                gpuLayers = lib.mkOption {
                  type = lib.types.int;
                  default = 999;
                  description = ''
                    Layers offloaded to the GPU. 999 means "all of them"; lower
                    it to keep VRAM free for Immich ML and Plex transcoding, or
                    to run a model that does not quite fit.
                  '';
                };

                contextSize = lib.mkOption {
                  type = lib.types.int;
                  default = 8192;
                  description = ''
                    Context window. This is real VRAM, so it is set explicitly
                    rather than inherited.
                  '';
                };

                ttl = lib.mkOption {
                  type = lib.types.int;
                  default = 300;
                  description = "Idle seconds before the model is unloaded and the VRAM released.";
                };

                aliases = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  example = [ "gpt-4o" ];
                  description = ''
                    Extra model names that resolve to this one, useful for
                    clients with a hardcoded model name.
                  '';
                };

                extraFlags = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                  example = [
                    "--parallel"
                    "2"
                  ];
                  description = "Additional llama-server flags for this model.";
                };
              };
            }
          )
        );
      };

      apiPort = lib.mkOption {
        type = lib.types.port;
        default = 11434;
        description = ''
          Port of the local LLM API, whichever backend serves it. Kept at
          Ollama's default so existing clients need no change; the
          OpenAI-compatible base URL is http://<host>:<port>/v1.
        '';
      };
      openWebuiPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Open WebUI port.";
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
        default = "01:00";
        description = "systemd calendar spec for `snapraid sync`.";
      };

      scrubInterval = lib.mkOption {
        type = lib.types.str;
        default = "Mon *-*-* 02:00:00";
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
