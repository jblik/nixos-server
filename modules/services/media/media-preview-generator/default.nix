{
  config,
  lib,
  pkgs,
  ...
}:
let
  maintenanceService = import ../../maintenance/service.nix { inherit config lib pkgs; };
  inherit (config.host.storage) bulkMount scratchDir;
  plex = config.services.plex;
  plexRoot = "${plex.dataDir}/Plex Media Server";
  stateDir = "/var/lib/media-preview-generator";
  port = config.host.media.mediaPreviewGenerator.port;
  nvidiaVulkanIcd = pkgs.runCommand "nvidia-egl-icd.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
    jq '.ICD.library_path = "/usr/local/nvidia/lib64/libEGL_nvidia.so.0"' \
      ${config.hardware.nvidia.package}/share/vulkan/icd.d/nvidia_icd.json > "$out"
  '';
in
{
  config = lib.mkIf config.host.media.enable {
    systemd.services.previews-maintenance = maintenanceService {
      task = "previews";
      description = "Apply the preview CPU worker maintenance window";
      unit = "podman-media-preview-generator.service";
      script = ./maintenance.py;
      environment = {
        PREVIEWS_URL = "http://127.0.0.1:${toString port}";
        PREVIEWS_AUTH = "${stateDir}/auth.json";
        PREVIEWS_CPU_WORKERS = toString config.host.maintenance.mediaPreviewGenerator.cpuWorkers;
      };
    };

    hardware.nvidia-container-toolkit.enable = true;
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    virtualisation.oci-containers.containers.media-preview-generator = {
      image = "docker.io/stevezzau/media_preview_generator:5.1.0";
      environment = {
        PUID = toString config.users.users.${plex.user}.uid;
        PGID = toString config.users.groups.${plex.group}.gid;
        TZ = config.time.timeZone;
        WEB_PORT = toString port;
        PLEX_BIF_FRAME_INTERVAL = "10";
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "all";
        VK_DRIVER_FILES = "/etc/vulkan/icd.d/nvidia_icd.json";
      };
      volumes = [
        "${stateDir}:/config"
        "${bulkMount}/media:${bulkMount}/media:ro"
        "${plexRoot}:/plex"
        # Explicitly expose the HDD directory rather than relying on nested mount propagation.
        "${bulkMount}/plex-media:/plex/Media"
        "${scratchDir}/plex-previews:/tmp"
        # The headless container can initialize Vulkan through EGL but not GLX.
        "${nvidiaVulkanIcd}:/etc/vulkan/icd.d/nvidia_icd.json:ro"
      ];
      extraOptions = [
        "--network=host"
        "--device=nvidia.com/gpu=all"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 ${plex.user} ${plex.group} -"
      "d ${bulkMount}/plex-media 0750 ${plex.user} ${plex.group} -"
      "d ${scratchDir}/plex-previews 0750 ${plex.user} ${plex.group} -"
    ];

    systemd.services.podman-media-preview-generator.unitConfig.RequiresMountsFor = [
      stateDir
      "${plexRoot}/Media"
      "${scratchDir}/plex-previews"
    ];

    networking.firewall.extraInputRules = ''
      ip saddr ${config.host.lanCidr} tcp dport ${toString port} accept
    '';
  };
}
