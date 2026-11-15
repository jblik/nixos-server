{
  config,
  lib,
  pkgs,
  ...
}:
let
  s = config.services;
  m = config.host.media;
  configure = pkgs.writers.writePython3 "sportarr-integrations" {
    libraries = with pkgs.python3Packages; [
      configobj
      requests
    ];
  } (builtins.readFile ./configure.py);
  dependencies = [
    "podman-sportarr.service"
    "prowlarr.service"
    "qbittorrent.service"
    "sabnzbd.service"
    "plex.service"
  ];
in
{
  config = lib.mkIf m.enable {
    # systemd 260 fails to deserialize credential source paths containing spaces.
    systemd.tmpfiles.rules = [
      "L /run/sportarr-plex.xml - - - - ${s.plex.dataDir}/Plex Media Server/Preferences.xml"
    ];

    systemd.services.sportarr-integrations = {
      description = "Configure Sportarr download clients, Prowlarr and Plex";
      wantedBy = [ "multi-user.target" ];
      requires = dependencies;
      after = dependencies;
      partOf = dependencies;
      unitConfig.StartLimitIntervalSec = 0;
      environment = {
        SPORTARR_URL = "http://127.0.0.1:${toString m.sportarr.port}";
        PROWLARR_URL = "http://127.0.0.1:${toString s.prowlarr.settings.server.port}";
        QBITTORRENT_URL = "http://127.0.0.1:${toString s.qbittorrent.webuiPort}";
        QBITTORRENT_PORT = toString s.qbittorrent.webuiPort;
        SABNZBD_PORT = toString s.sabnzbd.settings.misc.port;
        PLEX_URL = "http://127.0.0.1:${toString m.plex.port}";
        SPORTS_ROOT = "${config.host.storage.bulkMount}/media/sports";
        SPORTS_TORRENTS = "${config.host.storage.bulkMount}/torrents/sports";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = configure;
        DynamicUser = true;
        LoadCredential = [
          "sportarr.xml:/var/lib/sportarr/config.xml"
          "prowlarr.xml:/var/lib/prowlarr/config.xml"
          "qbittorrent.conf:${s.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"
          "sabnzbd.ini:/var/lib/${s.sabnzbd.stateDir}/sabnzbd.ini"
          "plex.xml:/run/sportarr-plex.xml"
        ];
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "5min";
      };
    };
  };
}
