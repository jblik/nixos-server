{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.host.media.enable {
    sops.secrets.pulsarr-settings = {
      sopsFile = ../../../secrets/media-pulsarr.yaml;
      key = "settings";
      restartUnits = [ "podman-pulsarr.service" ];
    };

    virtualisation.oci-containers.containers.pulsarr = {
      image = "lakker/pulsarr:0.19.7";
      environment = {
        PUID = "99";
        PGID = "100";
        listenPort = toString config.host.media.pulsarr.port;
        TZ = config.time.timeZone;
      };
      volumes = [ "/var/lib/pulsarr:/app/data" ];
      extraOptions = [ "--network=host" ];
    };

    systemd.tmpfiles.rules = [ "d /var/lib/pulsarr 0750 99 100 -" ];
    systemd.services.podman-pulsarr = {
      unitConfig.RequiresMountsFor = [ "/var/lib/pulsarr" ];
      preStart = lib.mkBefore ''
        umask 077
        ${pkgs.coreutils}/bin/install -d -m 0750 -o 99 -g 100 /var/lib/pulsarr/db
        ${pkgs.python3}/bin/python ${./settings/sqlite-settings.py} \
          ${./settings/pulsarr.json} \
          ${config.sops.secrets.pulsarr-settings.path} \
          /var/lib/pulsarr/db/pulsarr.db
        ${pkgs.coreutils}/bin/chown 99:100 /var/lib/pulsarr/db/pulsarr.db
      '';
    };
  };
}
