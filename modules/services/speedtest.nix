{
  config,
  lib,
  pkgs,
  ...
}:
let
  runtimeDir = "/run/speedtest";
  metricsDir = "/run/prometheus-textfile";

  speedtest = pkgs.writeShellApplication {
    name = "speedtest-metrics";
    runtimeInputs = with pkgs; [
      ookla-speedtest
      jq
    ];
    text = builtins.readFile ./speedtest.sh;
  };
in
{
  config = lib.mkIf config.host.dashboard.enable {
    services.prometheus.exporters.node.extraFlags = [
      "--collector.textfile.directory=${metricsDir}"
    ];

    systemd.tmpfiles.rules = [ "d ${metricsDir} 0755 speedtest speedtest -" ];

    systemd.services.speedtest = {
      description = "Measure the internet connection";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      startAt = "00/1:00";
      environment = {
        HOME = runtimeDir;
        METRICS_DIRECTORY = metricsDir;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe speedtest;
        User = "speedtest";
        Group = "speedtest";
        RuntimeDirectory = "speedtest";
        RuntimeDirectoryPreserve = true;
      };
    };

    systemd.services.speedtest-nordvpn = lib.mkIf config.host.media.enable {
      description = "Measure the NordVPN connection";
      requires = [ "qbittorrent-vpn.service" ];
      after = [ "qbittorrent-vpn.service" ];
      partOf = [ "qbittorrent-vpn.service" ];
      startAt = "00/1:30";
      environment = {
        HOME = "/run/speedtest-nordvpn";
        METRICS_DIRECTORY = metricsDir;
        SPEEDTEST_PREFIX = "nordvpn_speedtest";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe speedtest} --interface=nordvpn";
        User = "speedtest";
        Group = "speedtest";
        RuntimeDirectory = "speedtest-nordvpn";
        RuntimeDirectoryPreserve = true;
      };
    };

    systemd.timers.speedtest-nordvpn = lib.mkIf config.host.media.enable {
      timerConfig = {
        OnBootSec = "15min";
        RandomizedDelaySec = "10min";
      };
    };

    users.users.speedtest = {
      isSystemUser = true;
      group = "speedtest";
    };
    users.groups.speedtest = { };

    systemd.timers.speedtest.timerConfig = {
      OnBootSec = "5min";
      RandomizedDelaySec = "10min";
    };
  };
}
