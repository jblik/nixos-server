{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.jackett;
in
{
  config = lib.mkIf config.host.media.enable {
    services.jackett = {
      enable = true;
      port = 9117;
    };

    sops.secrets.jackett-settings = {
      sopsFile = ../../../secrets/media-jackett.yaml;
      key = "settings";
      owner = cfg.user;
      group = cfg.group;
      restartUnits = [ "jackett.service" ];
    };

    systemd.services.jackett.preStart = ''
      umask 077
      ${pkgs.python3}/bin/python ${./settings/files-settings.py} \
        ${./settings/jackett.json} \
        ${config.sops.secrets.jackett-settings.path} \
        ${lib.escapeShellArg cfg.dataDir}
    '';

    # Not a StateDirectory, so nothing else stops Jackett from running without its dataset.
    systemd.services.jackett.unitConfig.RequiresMountsFor = [ config.services.jackett.dataDir ];
  };
}
