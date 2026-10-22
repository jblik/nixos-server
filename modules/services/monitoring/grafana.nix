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
    let
      selector = ''{device="${device}",channel="${channel}"}'';
    in
    {
      inherit name;
      rpm = "coolercontrol_fan_rpm${selector}";
      pwm = "coolercontrol_duty_percent${selector}";
      stopped = "(coolercontrol_duty_percent${selector} > bool 0) * (coolercontrol_fan_rpm${selector} == bool 0)";
    };
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

  fanStatus = {
    description = "PWM > 0% with RPM = 0 means rotation is requested but not reported. Brief flags can occur during startup. Missing readings remain unknown.";
    fieldConfig.defaults = {
      min = 0;
      max = 1;
      noValue = "Unknown";
      mappings = [
        {
          type = "value";
          options = {
            "0" = {
              text = "OK";
              color = "green";
            };
            "1" = {
              text = "No rotation";
              color = "red";
            };
          };
        }
      ];
    };
  };

  fanStatusTargets = map (f: target f.stopped f.name) fans;

  fanDashboard = {
    title = "Fans";
    uid = "fans";
    timezone = "browser";
    refresh = "30s";
    time = {
      from = "now-6h";
      to = "now";
    };
    schemaVersion = 39;
    panels = [
      (panel "stat" "Requested but not spinning — now" 0 0 24 4 (map (
        t: t // { instant = true; }
      ) fanStatusTargets) (fanStatus // { options.colorMode = "background"; }))
      (panel "state-timeline" "Requested but not spinning — history" 0 4 24 7 fanStatusTargets fanStatus)
    ]
    ++ lib.imap0 (
      i: f:
      panel "timeseries" f.name (lib.mod i 2 * 12) (11 + builtins.div i 2 * 8) 12 8
        [
          (target f.rpm "RPM")
          (target f.pwm "PWM")
        ]
        {
          fieldConfig = {
            defaults = {
              unit = "rotrpm";
              min = 0;
              custom.axisPlacement = "left";
            };
            overrides = [
              {
                matcher = {
                  id = "byName";
                  options = "PWM";
                };
                properties = [
                  {
                    id = "unit";
                    value = "percent";
                  }
                  {
                    id = "max";
                    value = 100;
                  }
                  {
                    id = "custom.axisPlacement";
                    value = "right";
                  }
                ];
              }
            ];
          };
          options = {
            tooltip.mode = "multi";
            legend = {
              displayMode = "table";
              placement = "bottom";
              calcs = [ "lastNotNull" ];
            };
          };
        }
    ) fans;
  };

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
      (panel "timeseries" "Fans — RPM" 12 4 12 9 (map (f: target f.rpm f.name) fans) (unit "rotrpm"))
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
      (panel "timeseries" "Fans — PWM" 0 31 12 9 (map (f: target f.pwm f.name) fans) {
        fieldConfig.defaults = {
          unit = "percent";
          min = 0;
          max = 100;
        };
        links = [
          {
            title = "Compare PWM and RPM per fan";
            url = "/d/fans";
          }
        ];
      })
      (panel "stat" "Fans — requested but not spinning" 12 31 12 9 (map (
        t: t // { instant = true; }
      ) fanStatusTargets) (fanStatus // { options.colorMode = "background"; }))
    ];
  };

  nordvpn = {
    title = "NordVPN";
    uid = "nordvpn";
    timezone = "browser";
    refresh = "30s";
    time = {
      from = "now-24h";
      to = "now";
    };
    schemaVersion = 39;
    panels = [
      (panel "stat" "NordVPN speed" 0 0 12 4 [
        (target "nordvpn_speedtest_download_bytes_per_second * 8" "Down")
        (target "nordvpn_speedtest_upload_bytes_per_second * 8" "Up")
      ] (unit "bps"))
      (panel "stat" "Last speedtest age" 12 0 12 4 [
        (target "time() - nordvpn_speedtest_timestamp_seconds" "Age")
      ] (unit "s"))
      (panel "timeseries" "Speed — NordVPN and host" 0 4 24 8 [
        (target "nordvpn_speedtest_download_bytes_per_second * 8" "NordVPN down")
        (target "nordvpn_speedtest_upload_bytes_per_second * 8" "NordVPN up")
        (target "speedtest_download_bytes_per_second * 8" "Host down")
        (target "speedtest_upload_bytes_per_second * 8" "Host up")
      ] (unit "bps"))
      (panel "timeseries" "NordVPN latency" 0 12 12 8 [
        (target "nordvpn_speedtest_ping_latency_seconds" "Idle")
        (target "nordvpn_speedtest_ping_jitter_seconds" "Jitter")
        (target "nordvpn_speedtest_download_latency_seconds" "During download")
        (target "nordvpn_speedtest_upload_latency_seconds" "During upload")
      ] (unit "s"))
      (panel "timeseries" "NordVPN packet loss" 12 12 12 8 [
        (target "nordvpn_speedtest_packet_loss_ratio" "Loss")
      ] percent)
    ];
  };

  qbittorrent = {
    title = "qBittorrent";
    uid = "qbittorrent";
    timezone = "browser";
    refresh = "30s";
    time = {
      from = "now-24h";
      to = "now";
    };
    schemaVersion = 39;
    panels = [
      (panel "stat" "Last collection age" 0 0 6 4 [
        (target "time() - qbittorrent_timestamp_seconds" "Age")
      ] (unit "s"))
      (panel "stat" "Torrents" 6 0 6 4 [ (target "qbittorrent_torrents" "Total") ] { })
      (panel "stat" "Remaining downloads" 12 0 6 4 [
        (target "qbittorrent_remaining_bytes" "Remaining")
      ] (unit "bytes"))
      (panel "stat" "Free download space" 18 0 6 4 [
        (target "qbittorrent_free_space_bytes" "Free")
      ] (unit "bytes"))
      (panel "timeseries" "Transfer speed" 0 4 12 8 [
        (target "qbittorrent_download_bytes_per_second" "Down")
        (target "qbittorrent_upload_bytes_per_second" "Up")
      ] (unit "Bps"))
      (panel "timeseries" "Torrents by state" 12 4 12 8 [
        (target "qbittorrent_torrents_by_state" "{{state}}")
      ] { })
      (panel "stat" "All-time transferred" 0 12 8 5 [
        (target "qbittorrent_downloaded_bytes_total" "Downloaded")
        (target "qbittorrent_uploaded_bytes_total" "Uploaded")
      ] (unit "bytes"))
      (panel "stat" "Session transferred" 8 12 8 5 [
        (target "qbittorrent_session_download_bytes" "Downloaded")
        (target "qbittorrent_session_upload_bytes" "Uploaded")
      ] (unit "bytes"))
      (panel "stat" "All-time share ratio" 16 12 8 5 [
        (target "qbittorrent_uploaded_bytes_total / clamp_min(qbittorrent_downloaded_bytes_total, 1)" "Ratio")
      ] { })
      (panel "timeseries" "Peers and DHT" 0 17 12 8 [
        (target "qbittorrent_peers" "Peer connections")
        (target "qbittorrent_dht_nodes" "DHT nodes")
      ] { })
      (panel "stat" "Connection status" 12 17 12 8 [
        ((target "qbittorrent_connection_status == 1" "{{status}}") // { instant = true; })
      ] { options.textMode = "name"; })
    ];
  };

  dashboards = pkgs.linkFarm "grafana-dashboards" (
    {
      "server.json" = pkgs.writeText "server.json" (builtins.toJSON server);
      "fans.json" = pkgs.writeText "fans.json" (builtins.toJSON fanDashboard);
      "node-exporter-full.json" =
        communityDashboard "node-exporter-full" 1860 45
          "sha256-GExrdAnzBtp1Ul13cvcZRbEM6iOtFrXXjEaY6g6lGYY=";
      "nvidia-gpu.json" =
        communityDashboard "nvidia-gpu" 14574 15
          "sha256-L1yXeL3LLnyPHlS0l30075gO+WS/WE3zXD8eNeR1r80=";
    }
    // lib.optionalAttrs host.media.enable {
      "nordvpn.json" = pkgs.writeText "nordvpn.json" (builtins.toJSON nordvpn);
      "qbittorrent.json" = pkgs.writeText "qbittorrent.json" (builtins.toJSON qbittorrent);
    }
  );

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
          http_port = host.dashboard.grafanaPort;
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
