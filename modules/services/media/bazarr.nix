{
  config,
  lib,
  pkgs,
  ...
}:
let
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
  cfg = config.services.bazarr;
in
{
  config = lib.mkIf config.host.media.enable {
    services.bazarr = {
      enable = true;
      group = "users";
      listenPort = 6767;
    };

    sops.secrets.bazarr-settings = {
      sopsFile = ../../../secrets/media-bazarr.yaml;
      key = "settings";
      owner = cfg.user;
      group = cfg.group;
      restartUnits = [ "bazarr.service" ];
    };

    systemd.services.bazarr.preStart = ''
      umask 077
      ${python}/bin/python ${./settings/files-settings.py} \
        ${./settings/bazarr.json} \
        ${config.sops.secrets.bazarr-settings.path} \
        ${lib.escapeShellArg cfg.dataDir}
      ${pkgs.python3}/bin/python ${./settings/sqlite-settings.py} \
        ${./settings/bazarr-database.json} \
        ${config.sops.secrets.bazarr-settings.path} \
        ${lib.escapeShellArg "${cfg.dataDir}/db/bazarr.db"}
    '';
  };
}
