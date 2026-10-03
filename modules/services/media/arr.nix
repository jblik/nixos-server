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
      settings.server.port = 8989;
    };
    services.radarr = {
      enable = true;
      group = "users";
      settings.server.port = 7878;
    };
    services.bazarr = {
      enable = true;
      group = "users";
      listenPort = 6767;
    };
    services.qbittorrent = {
      enable = true;
      group = "users";
      webuiPort = 8080;
    };
    services.jackett = {
      enable = true;
      port = 9117;
    };
    services.flaresolverr = {
      enable = true;
      port = 8191;
    };

    # Not StateDirectories, so nothing else stops these from running without their datasets.
    systemd.services.qbittorrent.unitConfig.RequiresMountsFor = [
      config.services.qbittorrent.profileDir
    ];
    systemd.services.jackett.unitConfig.RequiresMountsFor = [ config.services.jackett.dataDir ];
  };
}
