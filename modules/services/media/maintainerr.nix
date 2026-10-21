{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.host.media.enable {
    sops.secrets.maintainerr-settings = {
      sopsFile = ../../../secrets/media-maintainerr.yaml;
      key = "settings";
      restartUnits = [ "podman-maintainerr.service" ];
    };

    virtualisation.oci-containers.containers.maintainerr = {
      image = "ghcr.io/maintainerr/maintainerr:latest";
      user = "99:100";
      environment = {
        UI_PORT = toString config.host.media.maintainerr.port;
        TZ = config.time.timeZone;
      };
      volumes = [ "/var/lib/maintainerr:/opt/data" ];
      extraOptions = [ "--network=host" ];
    };

    systemd.tmpfiles.rules = [ "d /var/lib/maintainerr 0750 99 100 -" ];
    systemd.services.podman-maintainerr = {
      unitConfig.RequiresMountsFor = [ "/var/lib/maintainerr" ];
      restartTriggers = [ ./maintainerr-settings.json ];
      preStart = ''
        umask 0077
        ${pkgs.python3}/bin/python3 ${./settings/sqlite-settings.py} \
          ${./maintainerr-settings.json} ${config.sops.secrets.maintainerr-settings.path} \
          /var/lib/maintainerr/maintainerr.sqlite
        chown 99:100 /var/lib/maintainerr/maintainerr.sqlite
        chmod 0600 /var/lib/maintainerr/maintainerr.sqlite
      '';
    };
  };
}
