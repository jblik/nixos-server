{ lib, ... }:
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
          "ollama.service"
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
      ollamaPort = lib.mkOption {
        type = lib.types.port;
        default = 11434;
        description = "Ollama API port (OpenAI-compatible at /v1).";
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
  };
}
