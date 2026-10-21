{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.host.media.enable {
    sops.secrets.cleanuparr-settings = {
      sopsFile = ../../../secrets/media-cleanuparr.yaml;
      key = "settings";
      restartUnits = [ "podman-cleanuparr.service" ];
    };

    virtualisation.oci-containers.containers.cleanuparr = {
      image = "ghcr.io/cleanuparr/cleanuparr:2.10.8";
      environment = {
        PUID = "99";
        PGID = "100";
        UMASK = "002";
        PORT = toString config.host.media.cleanuparr.port;
        TZ = config.time.timeZone;
      };
      volumes = [
        "/var/lib/cleanuparr:/config"
        "${config.host.storage.bulkMount}/torrents:${config.host.storage.bulkMount}/torrents"
        "${./cleanuparr-blocklist.txt}:/blocklist.txt:ro"
      ];
      extraOptions = [ "--network=host" ];
    };

    systemd.tmpfiles.rules = [ "d /var/lib/cleanuparr 0750 99 100 -" ];
    systemd.services.podman-cleanuparr = {
      unitConfig.RequiresMountsFor = [
        "/var/lib/cleanuparr"
        config.host.storage.bulkMount
      ];
      restartTriggers = [
        ./cleanuparr-settings.json
        ./settings/sqlite-settings.py
      ];
      preStart = ''
        umask 0077
        ${pkgs.python3}/bin/python3 ${./settings/sqlite-settings.py} \
          ${./cleanuparr-settings.json} ${config.sops.secrets.cleanuparr-settings.path} \
          /var/lib/cleanuparr/cleanuparr.db
        chown 99:100 /var/lib/cleanuparr/cleanuparr.db
        chmod 0600 /var/lib/cleanuparr/cleanuparr.db
      '';
    };
  };
}
