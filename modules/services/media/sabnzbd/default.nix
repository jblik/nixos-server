{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.host.storage) scratchDir;
  s = config.services;
  configure = pkgs.writers.writePython3 "sabnzbd-arr" {
    libraries = with pkgs.python3Packages; [
      configobj
      requests
    ];
  } (builtins.readFile ./arr.py);
in
{
  config = lib.mkIf config.host.media.enable {
    services.sabnzbd = {
      enable = true;
      group = "users";
      configFile = null;
      allowConfigWrite = true;
      settings = {
        misc = {
          host = "127.0.0.1";
          port = config.host.media.sabnzbd.port;
          host_whitelist = "sabnzbd.internal.steenblik.ch";
          download_dir = "${scratchDir}/usenet/incomplete";
          complete_dir = "${scratchDir}/usenet/complete";
          permissions = "0775";
        };
        categories = {
          tv = {
            name = "tv";
            dir = "tv";
            pp = 3;
          };
          movies = {
            name = "movies";
            dir = "movies";
            pp = 3;
          };
        };
      };
    };

    systemd.services = {
      sabnzbd = {
        unitConfig.RequiresMountsFor = [
          "/var/lib/${s.sabnzbd.stateDir}"
          scratchDir
        ];
        serviceConfig.UMask = "0002";
      };
    }
    // lib.genAttrs [ "sonarr-sabnzbd" "radarr-sabnzbd" ] (
      name:
      let
        app = lib.removeSuffix "-sabnzbd" name;
      in
      {
        description = "Configure SABnzbd in ${app}";
        wantedBy = [ "multi-user.target" ];
        requires = [
          "${app}.service"
          "sabnzbd.service"
        ];
        after = [
          "${app}.service"
          "sabnzbd.service"
        ];
        environment = {
          ARR_URL = "http://127.0.0.1:${toString s.${app}.settings.server.port}";
          SABNZBD_PORT = toString s.sabnzbd.settings.misc.port;
          CATEGORY = if app == "sonarr" then "tv" else "movies";
          CATEGORY_FIELD = if app == "sonarr" then "tvCategory" else "movieCategory";
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = configure;
          DynamicUser = true;
          LoadCredential = [
            "sabnzbd.ini:/var/lib/${s.sabnzbd.stateDir}/sabnzbd.ini"
            "arr.xml:${s.${app}.dataDir}/config.xml"
          ];
          Restart = "on-failure";
          RestartSec = "10s";
        };
      }
    );
  };
}
