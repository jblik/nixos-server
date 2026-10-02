{ config, lib, ... }:
# *arr helpers that have no NixOS module. Host networking so they reach Plex and
# the *arr apps on localhost; all run as 99:100 like on unraid.
let
  inherit (config.host.storage) bulkMount;
  m = config.host.media;
  uid = "99";
  gid = "100";
  containers = {
    cleanuparr = {
      image = "ghcr.io/cleanuparr/cleanuparr:latest";
      environment = {
        PUID = uid;
        PGID = gid;
        UMASK = "002";
        PORT = toString m.cleanuparr.port;
      };
      # Same path as qBittorrent sees, so the torrent paths it reports resolve.
      volumes = [
        "/var/lib/cleanuparr:/config"
        "${bulkMount}/torrents:${bulkMount}/torrents"
        "${./cleanuparr-blocklist.txt}:/blocklist.txt:ro"
      ];
    };

    pulsarr = {
      image = "lakker/pulsarr:latest";
      environment = {
        PUID = uid;
        PGID = gid;
        listenPort = toString m.pulsarr.port;
      };
      volumes = [ "/var/lib/pulsarr:/app/data" ];
    };

    maintainerr = {
      image = "ghcr.io/maintainerr/maintainerr:latest";
      user = "${uid}:${gid}";
      environment.UI_PORT = toString m.maintainerr.port;
      volumes = [ "/var/lib/maintainerr:/opt/data" ];
    };
  };
in
{
  config = lib.mkIf m.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    systemd.tmpfiles.rules = map (d: "d /var/lib/${d} 0750 ${uid} ${gid} -") (lib.attrNames containers);

    virtualisation.oci-containers.containers = lib.mapAttrs (
      _: c:
      lib.recursiveUpdate c {
        environment.TZ = config.time.timeZone;
        extraOptions = [ "--network=host" ];
      }
    ) containers;

    # Podman fails with exit 125 if the bind-mount source is missing.
    systemd.services.podman-cleanuparr.unitConfig.RequiresMountsFor = [ bulkMount ];
  };
}
