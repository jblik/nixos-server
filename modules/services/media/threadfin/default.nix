{
  config,
  lib,
  pkgs,
  ...
}:
let
  port = config.host.media.threadfin.port;
  stateDir = "/var/lib/threadfin";
  configure = pkgs.writers.writePython3 "threadfin-xmltv" {
    libraries = [ pkgs.python3Packages.websockets ];
  } (builtins.readFile ./configure.py);
  settings = pkgs.writeText "threadfin-settings.json" (
    builtins.toJSON {
      buffer = "ffmpeg";
      bindIpAddress = "127.0.0.1";
      epgSource = "PMS";
      ssdp = false;
      ThreadfinAutoUpdate = false;
      httpThreadfinDomain = "127.0.0.1:${toString port}";
      version = "0.5.0";
      "ffmpeg.options" =
        "-hide_banner -loglevel error -analyzeduration 1000000 -probesize 1000000 -i [URL] -c:v copy -c:a aac -b:a 192k -ac 2 -sn -f mpegts -fflags +genpts -movflags +faststart -copyts pipe:1";
      files = {
        m3u.M0000000000000000001 = {
          name = "Verified Swiss IPTV";
          type = "m3u";
          "file.source" = "/channels.m3u";
          buffer = "ffmpeg";
          tuner = 1;
        };
        xmltv = { };
        hdhr = { };
      };
    }
  );
in
{
  config = lib.mkIf config.host.media.enable {
    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.threadfin = {
      image = "docker.io/fyb3roptik/threadfin:1.2.37";
      user = "99:100";
      environment = {
        TZ = config.time.timeZone;
        THREADFIN_PORT = toString port;
        THREADFIN_BIND_IP_ADDRESS = "127.0.0.1";
      };
      volumes = [
        "${stateDir}:/home/threadfin/conf"
        "${./channels.m3u}:/channels.m3u:ro"
      ];
      extraOptions = [ "--network=host" ];
    };

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0750 99 100 -"
      "C ${stateDir}/settings.json 0640 99 100 - ${settings}"
    ];
    systemd.services.podman-threadfin = {
      unitConfig.RequiresMountsFor = [ stateDir ];
      preStart = ''
        ${pkgs.systemd}/bin/systemd-tmpfiles --create --prefix=${stateDir}
      '';
    };
    systemd.services.threadfin-xmltv = {
      description = "Configure IPTV guide sources and channel mappings";
      wantedBy = [ "multi-user.target" ];
      requires = [ "podman-threadfin.service" ];
      after = [ "podman-threadfin.service" ];
      partOf = [ "podman-threadfin.service" ];
      unitConfig.StartLimitIntervalSec = 0;
      environment = {
        THREADFIN_URL = "ws://127.0.0.1:${toString port}/data/";
        GUIDE_MAPPING = toString ./guide-mapping.json;
        PLAYLIST_FILE = toString ./channels.m3u;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = configure;
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = "20min";
      };
    };
  };
}
