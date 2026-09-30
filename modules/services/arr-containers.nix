{ config, lib, ... }:
# *arr helpers that have no NixOS module. Host networking so they reach Plex and
# the *arr apps on localhost; all run as 99:100 like on unraid.
let
  inherit (config.host.storage) bulkMount;
  tz = config.time.timeZone;
  lan = config.host.lanCidr;
  ports = [
    11011 # cleanuparr
    3003 # pulsarr
    6246 # maintainerr
  ];
in
{
  config = lib.mkIf config.host.media.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    systemd.tmpfiles.rules = map (d: "d /var/lib/${d} 0750 99 100 -") [
      "cleanuparr"
      "pulsarr"
      "maintainerr"
    ];

    virtualisation.oci-containers.containers = {
      cleanuparr = {
        image = "ghcr.io/cleanuparr/cleanuparr:latest";
        environment = {
          TZ = tz;
          PUID = "99";
          PGID = "100";
          UMASK = "002";
          PORT = "11011";
        };
        # Same path as qBittorrent sees, so the torrent paths it reports resolve.
        volumes = [
          "/var/lib/cleanuparr:/config"
          "${bulkMount}/torrents:${bulkMount}/torrents"
        ];
        extraOptions = [ "--network=host" ];
      };

      pulsarr = {
        image = "lakker/pulsarr:latest";
        environment = {
          TZ = tz;
          PUID = "99";
          PGID = "100";
        };
        volumes = [ "/var/lib/pulsarr:/app/data" ];
        extraOptions = [ "--network=host" ];
      };

      maintainerr = {
        image = "ghcr.io/maintainerr/maintainerr:latest";
        user = "99:100";
        environment.TZ = tz;
        volumes = [ "/var/lib/maintainerr:/opt/data" ];
        extraOptions = [ "--network=host" ];
      };
    };

    # Podman fails with exit 125 if the bind-mount source is missing.
    systemd.services.podman-cleanuparr.unitConfig.RequiresMountsFor = [ bulkMount ];

    networking.firewall.extraInputRules = ''
      ip saddr ${lan} tcp dport { ${lib.concatMapStringsSep ", " toString ports} } accept
    '';
  };
}
