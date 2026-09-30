{ config, lib, ... }:
# The *arr stack, native. Web UIs are LAN-only; FlareSolverr is only used by
# Jackett on this host, so it stays closed.
let
  lan = config.host.lanCidr;
  s = config.services;
  ports = [
    s.sonarr.settings.server.port
    s.radarr.settings.server.port
    s.bazarr.listenPort
    s.jackett.port
    s.qbittorrent.webuiPort
    s.seerr.port
  ];
in
{
  config = lib.mkIf config.host.media.enable {
    services.sonarr = {
      enable = true;
      group = "users";
    };
    services.radarr = {
      enable = true;
      group = "users";
    };
    services.bazarr = {
      enable = true;
      group = "users";
    };
    services.qbittorrent = {
      enable = true;
      group = "users";
    };
    services.jackett.enable = true;
    services.flaresolverr.enable = true;
    services.seerr.enable = true;

    networking.firewall.extraInputRules = ''
      ip saddr ${lan} tcp dport { ${lib.concatMapStringsSep ", " toString ports} } accept
    '';
  };
}
