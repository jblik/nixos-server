{
  config,
  lib,
  pkgs,
  ...
}:
# An Ookla speedtest every six hours for the dashboard's network card. The result reaches
# the dashboard through node_exporter's textfile collector. A gigabit run moves ~1 GB.
let
  runtimeDir = "/run/speedtest";

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
      "--collector.textfile.directory=${runtimeDir}"
    ];

    systemd.services.speedtest = {
      description = "Measure the internet connection";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      startAt = "00/6:00";
      environment.HOME = runtimeDir;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe speedtest;
        DynamicUser = true;
        RuntimeDirectory = "speedtest";
        # The last result must outlive the run for node_exporter to read it.
        RuntimeDirectoryPreserve = true;
      };
    };

    # The result lives in /run, so measure again soon after a reboot.
    systemd.timers.speedtest.timerConfig = {
      OnBootSec = "5min";
      RandomizedDelaySec = "10min";
    };
  };
}
