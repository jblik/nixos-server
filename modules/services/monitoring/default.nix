{ config, lib, ... }:
# Alerts on the metrics Prometheus collects (modules/services/dashboard.nix), mailed to me
# by Alertmanager. Grafana (./grafana.nix) shows them next to the dashboards.
let
  host = config.host;
  storage = host.storage;
  alertmanager = config.services.prometheus.alertmanager;

  rule = alert: severity: for: expr: summary: {
    inherit alert expr for;
    labels = { inherit severity; };
    annotations = { inherit summary; };
  };

  # The dashboard calls a sensor hot at the same readings (server-dashboard's Readings.fs).
  hot = {
    Cpu = 85;
    Gpu = 85;
    Board = 75;
    Chipset = 90;
    Hdd = 55;
    Ssd = 70;
    Nvme = 75;
  };

  temperature =
    part:
    lib.recursiveUpdate (rule "TemperatureHot" "critical" "5m"
      ''coolercontrol_temperature_celsius{device="${part.device}",sensor="${part.sensor}"} >= ${toString hot.${part.kind}}''
      "${part.name} is at {{ $value | printf \"%.0f\" }} °C"
    ) { labels.part = part.name; };

  mounts = [
    storage.bulkMount
    "/"
    "/boot"
  ]
  ++ lib.attrValues storage.dataDisks;
  mountMatcher = ''mountpoint=~"${lib.concatStringsSep "|" mounts}"'';
  free = "node_filesystem_avail_bytes{${mountMatcher}} / node_filesystem_size_bytes{${mountMatcher}}";

  rules = [
    (rule "TargetDown" "warning" "5m" "up == 0" "Prometheus cannot scrape {{ $labels.job }}")
    (rule "UnitFailed" "warning" "1m" ''node_systemd_unit_state{state="failed"} == 1''
      "{{ $labels.name }} failed"
    )
    (rule "FilesystemAlmostFull" "warning" "15m" "${free} < 0.10"
      "{{ $labels.mountpoint }} has {{ $value | humanizePercentage }} free"
    )
    (rule "FilesystemFull" "critical" "5m" "${free} < 0.05"
      "{{ $labels.mountpoint }} has {{ $value | humanizePercentage }} free"
    )
    (rule "MemoryLow" "warning" "15m"
      "node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10"
      "Only {{ $value | humanizePercentage }} of memory is available"
    )
    (rule "OomKill" "warning" "0m" "increase(node_vmstat_oom_kill[10m]) > 0"
      "The kernel killed a process for lack of memory"
    )
    # speedtest.nix runs every six hours.
    (rule "SpeedtestStale" "warning" "0m" "time() - speedtest_timestamp_seconds > 13 * 3600"
      "No speedtest result for {{ $value | humanizeDuration }}"
    )
  ]
  ++ lib.optionals (storage.fastPool != null) [
    (rule "ZfsPoolUnhealthy" "critical" "0m" "zfs_pool_health != 0"
      "ZFS pool {{ $labels.pool }} is not ONLINE"
    )
    # ZFS slows down once a pool is past about 80 %.
    (rule "ZfsPoolAlmostFull" "warning" "15m" "zfs_pool_free_bytes / zfs_pool_size_bytes < 0.20"
      "ZFS pool {{ $labels.pool }} has {{ $value | humanizePercentage }} free"
    )
  ]
  ++ map temperature (lib.attrValues host.sensors);
in
{
  imports = [ ./grafana.nix ];

  config = lib.mkIf host.dashboard.enable {
    services.prometheus.exporters.node.enabledCollectors = [ "systemd" ];

    services.prometheus = {
      rules = [
        (builtins.toJSON {
          groups = [
            {
              name = "server";
              inherit rules;
            }
          ];
        })
      ];
      alertmanagers = [
        { static_configs = [ { targets = [ "127.0.0.1:${toString alertmanager.port}" ]; } ]; }
      ];
    };

    # The iCloud app password Paperless sends mail with.
    sops.secrets."paperless.env" = { };

    services.prometheus.alertmanager = {
      enable = true;
      listenAddress = "127.0.0.1";
      # todo consolidate and make it a better file so I don't reuse specific things
      environmentFile = config.sops.secrets."paperless.env".path;
      configuration = {
        route = {
          receiver = "email";
          group_by = [ "alertname" ];
          repeat_interval = "12h";
        };
        receivers = [
          {
            name = "email";
            email_configs = [
              {
                to = "jacob@steenblik.ch";
                from = "noreply@steenblik.ch";
                smarthost = "smtp.mail.me.com:587";
                auth_username = "$PAPERLESS_EMAIL_HOST_USER";
                auth_password = "$PAPERLESS_EMAIL_HOST_PASSWORD";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };
  };
}
