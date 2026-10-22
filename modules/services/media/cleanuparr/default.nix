{ config, lib, ... }:
let
  inherit (config.host.storage) bulkMount;
  uid = "99";
  gid = "100";
in
{
  config = lib.mkIf config.host.media.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    virtualisation.oci-containers.containers.cleanuparr = {
      extraOptions = [ "--network=host" ];
      image = "ghcr.io/cleanuparr/cleanuparr:2.10.12";
      environment = {
        TZ = config.time.timeZone;
        PUID = uid;
        PGID = gid;
        UMASK = "002";
        PORT = toString config.host.media.cleanuparr.port;
      };
      # Same path as qBittorrent sees, so the torrent paths it reports resolve.
      volumes = [
        "/var/lib/cleanuparr:/config"
        "${bulkMount}/torrents:${bulkMount}/torrents"
        "${./blocklist.txt}:/blocklist.txt:ro"
      ];
    };

    systemd.tmpfiles.rules = [ "d /var/lib/cleanuparr 0750 ${uid} ${gid} -" ];
    systemd.services.podman-cleanuparr.unitConfig.RequiresMountsFor = [
      "/var/lib/cleanuparr"
      bulkMount
    ];
  };
}
