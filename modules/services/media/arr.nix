{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.host.media.enable {
    services.sonarr = {
      enable = true;
      group = "users";
      settings.server.port = config.host.media.sonarr.port;
    };
    services.radarr = {
      enable = true;
      group = "users";
      settings.server.port = config.host.media.radarr.port;
    };
    services.bazarr = {
      enable = true;
      group = "users";
      listenPort = config.host.media.bazarr.port;
    };
    services.prowlarr = {
      enable = true;
      settings.server.port = config.host.media.prowlarr.port;
    };
    services.flaresolverr = {
      enable = true;
      port = config.host.media.flaresolverr.port;
    };

    # DynamicUser makes /var/lib/prowlarr a symlink, which RequiresMountsFor does not follow.
    systemd.services.prowlarr.unitConfig.RequiresMountsFor = [ "/var/lib/private/prowlarr" ];
  };
}
