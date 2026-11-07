{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.host.storage) scratchDir;
  s = config.services;
  smtpPort = config.host.networking.smtpPort;
  configure = pkgs.writers.writePython3 "sabnzbd-arr" {
    libraries = with pkgs.python3Packages; [
      configobj
      requests
    ];
  } (builtins.readFile ./arr.py);
in
{
  config = lib.mkIf config.host.media.enable {
    sops.secrets.sabnzbd-smtp-username = {
      key = "apple-username";
      owner = s.sabnzbd.user;
    };
    sops.secrets.sabnzbd-smtp-password = {
      key = "apple-token";
      owner = s.sabnzbd.user;
    };

    services.sabnzbd = {
      enable = true;
      group = "users";
      configFile = null;
      allowConfigWrite = true;
      secretValues = {
        "@smtp-username@" = config.sops.secrets.sabnzbd-smtp-username.path;
        "@smtp-password@" = config.sops.secrets.sabnzbd-smtp-password.path;
      };
      settings = {
        misc = {
          host = "127.0.0.1";
          port = config.host.media.sabnzbd.port;
          host_whitelist = "sabnzbd.internal.steenblik.ch";
          local_ranges = lib.concatStringsSep ", " [
            "127.0.0.0/8"
            "::1/128"
            config.host.lanCidr
            "100.64.0.0/10"
            "fd7a:115c:a1e0::/48"
          ];
          download_dir = "${scratchDir}/usenet/incomplete";
          complete_dir = "${scratchDir}/usenet/complete";
          permissions = "0775";
          email_server = "smtp.mail.me.com:${toString smtpPort}";
          email_account = "@smtp-username@";
          email_pwd = "@smtp-password@";
          email_from = "sabnzbd@steenblik.ch";
          email_to = "jacob@steenblik.ch";
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
