{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = config.services.sonarr.dataDir;
  secret = config.sops.secrets.media-sonarr-settings;
in
{
  config = lib.mkIf config.host.media.enable {
    services.sonarr = {
      enable = true;
      group = "users";
      settings.server.port = 8989;
    };

    sops.secrets.media-sonarr-settings = {
      sopsFile = ../../../secrets/media-sonarr.yaml;
      key = "settings";
      owner = "sonarr";
    };

    systemd.services.sonarr = {
      restartTriggers = [
        ./sonarr-settings.json
        ../../../secrets/media-sonarr.yaml
        ./settings/arr-settings.py
      ];
      preStart = lib.mkBefore ''
        ${pkgs.python3}/bin/python3 ${./settings/arr-settings.py} \
          ${./sonarr-settings.json} ${secret.path} \
          ${dataDir}/sonarr.db ${dataDir}/config.xml
      '';
    };
  };
}
