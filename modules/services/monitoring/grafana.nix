{
  config,
  lib,
  pkgs,
  ...
}:
# Grafana at grafana.internal.steenblik.ch: the history of what Prometheus collects, and
# the alerts from ./default.nix, which can be silenced there. Sign in as `admin` with the
# `grafana-admin-password` secret.
let
  host = config.host;
  storage = host.storage;
  s = config.services;

  datasource = {
    type = "prometheus";
    uid = "prometheus";
  };

  communityDashboard =
    name: id: revision: hash:
    pkgs.fetchurl {
      name = "${name}.json";
      url = "https://grafana.com/api/dashboards/${toString id}/revisions/${toString revision}/download";
      inherit hash;
    };

  target = expr: legendFormat: { inherit expr legendFormat; };

  panel =
    type: title: x: y: w: h: targets: extra:
    {
      inherit type title datasource;
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      targets = lib.imap0 (i: t: t // { refId = lib.elemAt lib.strings.upperChars i; }) targets;
    }
    // extra;

  unit = unit': {
    fieldConfig.defaults.unit = unit';
  };

  percent = lib.recursiveUpdate (unit "percentunit") {
    fieldConfig.defaults = {
      min = 0;
      max = 1;
    };
  };

  # A spun-down Hdd reads 0 °C; leaving those out keeps the graph's scale.
  temperature =
    part:
    target ''coolercontrol_temperature_celsius{device="${part.device}",sensor="${part.sensor}"}${lib.optionalString (part.kind == "Hdd") " > 0"}'' part.name;

  # The same fans and names as the dashboard (modules/services/dashboard.nix).
  fan =
    name: device: channel:
    target ''coolercontrol_fan_rpm{device="${device}",channel="${channel}"}'' name;
  board = host.sensors.motherboard.device;
  gpu = host.sensors.gpu.device;
  fans = [
    (fan "Front 1" board "fan1")
    (fan "Front 2" board "fan4")
    (fan "Front 3" board "fan3")
    (fan "Rear" board "fan6")
    (fan "CPU" board "fan2")
    (fan "Chipset" board "fan5")
    (fan "GPU 1" gpu "fan1")
    (fan "GPU 2" gpu "fan2")
  ];

  mounts = [
    storage.bulkMount
    "/"
    "/boot"
  ]
  ++ lib.attrValues storage.dataDisks;
  mountMatcher = ''mountpoint=~"${lib.concatStringsSep "|" mounts}"'';

  server = {
    title = "Server";
    uid = "server";
    timezone = "browser";
    refresh = "30s";
    time = {
      from = "now-24h";
      to = "now";
    };
    schemaVersion = 39;
    panels = [
      (panel "stat" "Firing alerts" 0 0 4 4
        [ (target ''count(ALERTS{alertstate="firing"}) or vector(0)'' "") ]
        {
          fieldConfig.defaults.thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "red";
                value = 1;
              }
            ];
          };
        }
      )
      (panel "stat" "Failed units" 4 0 8 4
        [ ((target ''node_systemd_unit_state{state="failed"} == 1'' "{{name}}") // { instant = true; }) ]
        {
          options.textMode = "name";
          fieldConfig.defaults = {
            noValue = "None";
            color = {
              mode = "fixed";
              fixedColor = "red";
            };
          };
        }
      )
      (panel "stat" "Uptime" 12 0 4 4 [ (target "time() - node_boot_time_seconds" "") ] (unit "s"))
      (panel "stat" "Internet" 16 0 8 4 [
        (target "speedtest_download_bytes_per_second * 8" "Down")
        (target "speedtest_upload_bytes_per_second * 8" "Up")
      ] (unit "bps"))
      (panel "timeseries" "Temperatures" 0 4 12 9 (map temperature (lib.attrValues host.sensors)) (
        unit "celsius"
      ))
      (panel "timeseries" "Fans" 12 4 12 9 fans (unit "rotrpm"))
      (panel "bargauge" "Disk usage" 0 13 12 9
        (
          [
            (target "1 - node_filesystem_avail_bytes{${mountMatcher}} / node_filesystem_size_bytes{${mountMatcher}}" "{{mountpoint}}")
          ]
          ++ lib.optionals (storage.fastPool != null) [
            (target "1 - zfs_pool_free_bytes / zfs_pool_size_bytes" "{{pool}} pool")
          ]
        )
        (
          lib.recursiveUpdate percent {
            options.displayMode = "gradient";
            fieldConfig.defaults.thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "green";
                  value = null;
                }
                {
                  color = "orange";
                  value = 0.8;
                }
                {
                  color = "red";
                  value = 0.9;
                }
              ];
            };
          }
        )
      )
      (panel "timeseries" "CPU and memory" 12 13 12 9 [
        (target ''1 - avg(rate(node_cpu_seconds_total{mode="idle"}[$__rate_interval]))'' "CPU")
        (target "1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes" "Memory")
      ] percent)
      (panel "timeseries" "GPU" 0 22 12 9 [
        (target "nvidia_smi_utilization_gpu_ratio" "Utilisation")
        (target "nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes" "Memory")
      ] percent)
      (panel "timeseries" "Internet speed" 12 22 12 9 [
        (target "speedtest_download_bytes_per_second * 8" "Down")
        (target "speedtest_upload_bytes_per_second * 8" "Up")
      ] (unit "bps"))
    ];
  };

  dashboards = pkgs.linkFarm "grafana-dashboards" {
    "server.json" = pkgs.writeText "server.json" (builtins.toJSON server);
    "node-exporter-full.json" =
      communityDashboard "node-exporter-full" 1860 45
        "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
    "nvidia-gpu.json" =
      communityDashboard "nvidia-gpu" 14574 15
        "sha256-L1yXeL3LLnyPHlS0l30075gO+WS/WE3zXD8eNeR1r80=";
  };

  secret = name: "$__file{${config.sops.secrets.${name}.path}}";
in
{
  config = lib.mkIf host.dashboard.enable {
    sops.secrets.grafana-secret-key.owner = "grafana";
    sops.secrets.grafana-admin-password.owner = "grafana";

    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          # Forgejo has 3000 and Gotenberg 3001.
          http_port = 3002;
          domain = "grafana.internal.steenblik.ch";
          root_url = "https://grafana.internal.steenblik.ch";
        };
        security = {
          secret_key = secret "grafana-secret-key";
          admin_password = secret "grafana-admin-password";
        };
        dashboards.default_home_dashboard_path = "${dashboards}/server.json";
      };
      provision = {
        enable = true;
        datasources.settings.datasources = [
          (
            datasource
            // {
              name = "Prometheus";
              url = "http://127.0.0.1:${toString s.prometheus.port}";
              isDefault = true;
            }
          )
          {
            name = "Alertmanager";
            type = "alertmanager";
            uid = "alertmanager";
            url = "http://127.0.0.1:${toString s.prometheus.alertmanager.port}";
            jsonData.implementation = "prometheus";
          }
        ];
        dashboards.settings.providers = [
          {
            name = "nix";
            options.path = dashboards;
          }
        ];
      };
    };
  };
}
