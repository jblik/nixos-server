{
  config,
  lib,
  pkgs-unstable,
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
      # Not older than unraid's, whose database gets imported; a downgrade can't open it.
      package = pkgs-unstable.radarr;
      group = "users";
      settings.server.port = 7878;
    };
    services.bazarr = {
      enable = true;
      # Not older than unraid's, whose database gets imported; a downgrade can't open it.
      package = pkgs-unstable.bazarr;
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
    services.seerr = {
      enable = true;
      port = 5055;
    };
  };
}
