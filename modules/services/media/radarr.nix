{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = config.services.radarr.dataDir;
  secret = config.sops.secrets.media-radarr-settings;
in
{
  config = lib.mkIf config.host.media.enable {
    services.radarr = {
      enable = true;
      group = "users";
      settings.server.port = 7878;
    };

    sops.secrets.media-radarr-settings = {
      sopsFile = ../../../secrets/media-radarr.yaml;
      key = "settings";
      owner = "radarr";
    };

    systemd.tmpfiles.rules = [ "d ${dataDir} 0750 radarr users - -" ];

    systemd.services.radarr = {
      restartTriggers = [
        ./radarr-settings.json
        ../../../secrets/media-radarr.yaml
        ./settings/arr-settings.py
      ];
      preStart = lib.mkBefore ''
        ${pkgs.python3}/bin/python3 ${./settings/arr-settings.py} \
          ${./radarr-settings.json} ${secret.path} \
          ${dataDir}/radarr.db ${dataDir}/config.xml
      '';
    };
  };
}
