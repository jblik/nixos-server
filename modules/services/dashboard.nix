{
  config,
  lib,
  inputs,
  ...
}:
# server.steenblik.ch shows the public services to everyone; from the LAN or tailnet the
# page also loads server.internal.steenblik.ch, which adds the internal services and the
# metrics node_exporter reports (temperatures, free space, fan speeds).
let
  host = config.host;

  icon = name: ext: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/${ext}/${name}.${ext}";

  service = name: description: subdomain: iconName: group: visibility: {
    Name = name;
    Description = description;
    Url =
      if visibility == "Public" then
        "https://${subdomain}.steenblik.ch"
      else
        "https://${subdomain}.internal.steenblik.ch";
    Icon = iconName;
    Group = group;
    Visibility = visibility;
  };

  services =
    lib.optionals host.media.enable [
      (service "Seerr" "Request movies and shows" "seerr" (icon "seerr" "svg") "Media" "Public")
      (service "Plex" "Stream the library" "plex" (icon "plex" "svg") "Media" "Internal")
      (service "Sonarr" "TV series" "sonarr" (icon "sonarr" "svg") "Media" "Internal")
      (service "Radarr" "Movies" "radarr" (icon "radarr" "svg") "Media" "Internal")
      (service "Bazarr" "Subtitles" "bazarr" (icon "bazarr" "svg") "Media" "Internal")
      (service "Jackett" "Indexer proxy" "jackett" (icon "jackett" "svg") "Media" "Internal")
      (service "qBittorrent" "Downloads" "qbittorrent" (icon "qbittorrent" "svg") "Media" "Internal")
      (service "Tdarr" "Transcoding on the RTX 3060" "tdarr" (icon "tdarr" "svg") "Media" "Internal")
      (service "Cleanuparr" "Clears stalled downloads" "cleanuparr" (icon "cleanuparr" "png") "Media"
        "Internal"
      )
      (service "Pulsarr" "Plex watchlist sync" "pulsarr" (icon "pulsarr" "svg") "Media" "Internal")
      (service "Maintainerr" "Library cleanup rules" "maintainerr" (icon "maintainerr" "svg") "Media"
        "Internal"
      )
    ]
    ++ lib.optionals host.immich.enable [
      (service "Photos" "Immich photo library" "photos" (icon "immich" "svg") "Library" "Public")
    ]
    ++ lib.optionals host.paperless.enable [
      (service "Paperless" "Scanned documents" "paperless" (icon "paperless-ngx" "svg") "Library"
        "Internal"
      )
    ]
    ++ lib.optionals host.forgejo.enable [
      (service "Git" "Forgejo" "git" (icon "forgejo" "svg") "Tools" "Public")
    ]
    ++ lib.optionals host.microbin.enable [
      (service "Notes" "MicroBin pastes" "notes" (icon "microbin" "png") "Tools" "Public")
    ];

  node = "node";
  coolercontrol = "coolercontrol";
  tokenCredential = "coolercontrol-token";

  label = name: value: {
    Name = name;
    Value = value;
  };

  # CoolerControl reports the same sensors its fan curves use (modules/hardware/fans.nix).
  reading = metric: key: label': device: value: {
    Label = label';
    Exporter = coolercontrol;
    Metric = "coolercontrol_${metric}";
    Labels = [
      (label "device" device)
      (label key value)
    ];
  };
  temperature = reading "temperature_celsius" "sensor";
  fan = reading "fan_rpm" "channel";

  cpu = "AMD Ryzen 7 2700X Eight-Core Processor";
  gpu = "NVIDIA GeForce RTX 3060";
  board = "nct6798";
in
{
  imports = [ inputs.server-dashboard.nixosModules.default ];

  config = lib.mkIf host.dashboard.enable {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      # Temperatures come from CoolerControl, which leaves a spun-down disk asleep; this
      # collector would wake it on every scrape.
      disabledCollectors = [ "hwmon" ];
    };

    systemd.services.server-dashboard = {
      wants = [ "coolercontrol-defaults.service" ];
      after = [ "coolercontrol-defaults.service" ];
      serviceConfig.LoadCredential = "${tokenCredential}:/var/lib/coolercontrol-defaults/dashboard-token";
    };

    services.server-dashboard = {
      enable = true;
      settings.Dashboard = {
        Services = services;
        Metrics = {
          Exporters = [
            {
              Name = node;
              Url = "http://127.0.0.1:${toString config.services.prometheus.exporters.node.port}/metrics";
            }
            {
              Name = coolercontrol;
              Url = "http://127.0.0.1:${toString host.fans.port}/metrics";
              TokenFile = "/run/credentials/server-dashboard.service/${tokenCredential}";
            }
          ];
          FanControl = coolercontrol;
          Temperatures = [
            # temp2 is Tdie; temp1 is Tctl, which carries a +10 °C offset on the 2700X.
            (temperature "CPU" cpu "temp2")
            (temperature "GPU" gpu "GPU Temp")
            (temperature "Chipset" board "temp9")
            (temperature "disk1" "ST10000NE0008-2P" "temp1")
            (temperature "SSD (SanDisk)" "SanDisk SSD PLUS" "temp1")
            (temperature "SSD (PEAQ)" "PEAQ    SSD_256G" "temp1")
            (temperature "NVMe" "nvme" "temp1")
          ];
          Disks = [
            {
              Label = "Bulk (/data)";
              Exporter = node;
              MountPoint = host.storage.bulkMount;
            }
            {
              Label = "Fast pool";
              Exporter = node;
              MountPoint = host.storage.fastDatasets.plex;
            }
            {
              Label = "NVMe (system, scratch)";
              Exporter = node;
              MountPoint = "/";
            }
          ];
          Fans = [
            (fan "Front 1" board "fan1")
            (fan "Front 2" board "fan3")
            (fan "Front 3" board "fan4")
            (fan "Rear" board "fan6")
            (fan "CPU" board "fan2")
            (fan "Chipset" board "fan5")
            (fan "GPU 1" gpu "fan1")
            (fan "GPU 2" gpu "fan2")
          ];
        };
      };
    };
  };
}
