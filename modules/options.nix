{ config, lib, ... }:
# Central, easily-changeable knobs for this server.
# Everything hardware- or site-specific should be expressed here and consumed
# by the other modules via `config.host.*`, so the rest of the tree stays generic.
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
        CPU vendor. Drives microcode and the IOMMU kernel parameter
        (amd_iommu=on vs intel_iommu=on). Flip this single value if the
        assumption is wrong.
      '';
    };

    lanCidr = lib.mkOption {
      type = lib.types.str;
      default = "192.168.0.0/16";
      description = ''
        LAN subnet allowed to reach the AI / ML endpoints. Tighten this to
        your actual subnet (e.g. "192.168.1.0/24").
      '';
    };

    gpu = {
      # PCI vendor:device IDs of the GPU *and its HDMI-audio function*, used to
      # reserve the card for vfio-pci. Find them with `lspci -nn | grep -i nvidia`
      # e.g. [ "10de:2204" "10de:1aef" ]  (GPU + audio).
      vendorIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "10de:2204"
          "10de:1aef"
        ];
        description = "PCI vendor:device IDs to reserve for VFIO passthrough.";
      };

      # PCI bus addresses of the same functions, used by libvirt hooks /
      # helper scripts to detach/attach. Find with `lspci -D | grep -i nvidia`
      # e.g. [ "0000:01:00.0" "0000:01:00.1" ].
      busIds = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "0000:01:00.0"
          "0000:01:00.1"
        ];
        description = "PCI bus addresses of the GPU functions for passthrough.";
      };

      # systemd units that hold the GPU on the host. They are stopped before a
      # passthrough VM starts and restarted after it shuts down.
      hostServices = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          (if config.host.ai.backend == "ollama" then "ollama.service" else "llama-swap.service")
          "podman-immich-machine-learning.service"
        ];
        description = "Host units to stop/start around GPU passthrough.";
      };

      # libvirt domain names that receive the GPU. The qemu hook only performs
      # the unbind/rebind dance for these guests.
      passthroughVms = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "steamos" ];
        description = "Domains that trigger GPU detach/attach via the qemu hook.";
      };
    };

    ai = {
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

          See docs/AI-BACKEND.md for the full comparison.
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
                    rather than inherited — see docs/AI-BACKEND.md §4.
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

    immich = {
      machineLearningPort = lib.mkOption {
        type = lib.types.port;
        default = 3003;
        description = ''
          Port the offloaded Immich machine-learning container listens on.
          Point the Immich server on unraid at http://<nixos>:<port> via
          IMMICH_MACHINE_LEARNING_URL.
        '';
      };
    };
    storage = {
      # --- Fast tier: ZFS mirror for service state, databases, models, VM images ---
      fastPool = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "fast";
        description = ''
          Name of the ZFS pool used for the fast tier. `null` disables all ZFS
          handling, so the bulk array can be used on its own.

          Create the pool once, by hand, before enabling this:
            zpool create -o ashift=12 -O compression=zstd -O atime=off fast \
              mirror /dev/disk/by-id/<ssd-a> /dev/disk/by-id/<ssd-b>
        '';
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

      # --- Bulk tier: mergerfs union over per-disk XFS, parity by SnapRAID ---
      bulkMount = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/storage";
        description = ''
          Mountpoint of the mergerfs union that services see as one filesystem.
          Keep downloads and the media library both under here, or hardlinks
          between them break and every import becomes a full copy.
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
          "/downloads/incomplete/"
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

      # --- Spin-down: unraid did this for you, systemd will not ---
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
