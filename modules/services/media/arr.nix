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
    services.jackett = {
      enable = true;
      port = config.host.media.jackett.port;
    };
    services.prowlarr = {
      enable = true;
      settings.server.port = config.host.media.prowlarr.port;
    };
    services.flaresolverr = {
      enable = true;
      port = config.host.media.flaresolverr.port;
    };

    # Not a StateDirectory, so nothing else stops Jackett from running without its dataset.
    systemd.services.jackett.unitConfig.RequiresMountsFor = [ config.services.jackett.dataDir ];
    # DynamicUser makes /var/lib/prowlarr a symlink, which RequiresMountsFor does not follow.
    systemd.services.prowlarr.unitConfig.RequiresMountsFor = [ "/var/lib/private/prowlarr" ];
  };
}
