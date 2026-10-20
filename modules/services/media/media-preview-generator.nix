{ config, lib, ... }:
let
  inherit (config.host.storage) bulkMount scratchDir;
  plex = config.services.plex;
  plexRoot = "${plex.dataDir}/Plex Media Server";
  stateDir = "/var/lib/media-preview-generator";
  port = 8280;
in
{
  config = lib.mkIf config.host.media.enable {
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
      };
      volumes = [
        "${stateDir}:/config"
        "${bulkMount}/media:${bulkMount}/media:ro"
        "${plexRoot}:/plex"
        # Explicitly expose the HDD directory rather than relying on nested mount propagation.
        "${bulkMount}/plex-media:/plex/Media"
        "${scratchDir}/plex-previews:/tmp"
        # CDI supplies the driver library but omits its Vulkan registration file.
        "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json:/etc/vulkan/icd.d/nvidia_icd.json:ro"
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
