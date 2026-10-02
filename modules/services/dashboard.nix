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
  storage = host.storage;

  publicDomain = "steenblik.ch";
  internalDomain = "internal.${publicDomain}";

  public = "Public";
  internal = "Internal";

  media = "Media";
  library = "Library";
  tools = "Tools";
  system = "System";

  icon = name: ext: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/${ext}/${name}.${ext}";
  svg = name: icon name "svg";
  png = name: icon name "png";

  # `subdomain` must match the host in modules/services/proxy.nix.
  service = group: visibility: subdomain: name: description: iconUrl: {
    Name = name;
    Description = description;
    Url =
      if visibility == public then
        "https://${subdomain}.${publicDomain}"
      else
        "https://${subdomain}.${internalDomain}";
    Icon = iconUrl;
    Group = group;
    Visibility = visibility;
  };

  services =
    lib.optionals host.media.enable [
      (service media internal "plex" "Plex" "Stream the library" (svg "plex"))
      (service media internal "sonarr" "Sonarr" "TV series" (svg "sonarr"))
      (service media internal "radarr" "Radarr" "Movies" (svg "radarr"))
      (service media internal "bazarr" "Bazarr" "Subtitles" (svg "bazarr"))
      (service media internal "jackett" "Jackett" "Indexer proxy" (svg "jackett"))
      (service media internal "qbittorrent" "qBittorrent" "Downloads" (svg "qbittorrent"))
      (service media internal "tdarr" "Tdarr" "Transcoding on the RTX 3060" (svg "tdarr"))
      (service media internal "cleanuparr" "Cleanuparr" "Clears stalled downloads" (png "cleanuparr"))
      (service media internal "pulsarr" "Pulsarr" "Plex watchlist sync" (svg "pulsarr"))
      (service media internal "maintainerr" "Maintainerr" "Library cleanup rules" (svg "maintainerr"))
    ]
    ++ lib.optionals host.immich.enable [
      (service library public "photos" "Photos" "Immich photo library" (svg "immich"))
    ]
    ++ lib.optionals host.paperless.enable [
      (service library public "documents" "Paperless" "Scanned documents" (svg "paperless-ngx"))
    ]
    ++ lib.optionals host.forgejo.enable [
      (service tools public "git" "Git" "Forgejo" (svg "forgejo"))
    ]
    ++ lib.optionals host.microbin.enable [
      (service tools public "notes" "Notes" "MicroBin pastes" (png "microbin"))
    ]
    ++ [
      (service system internal "fans" "Fans" "CoolerControl fan curves" (svg "cooler-control"))
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

  disk = label': mountPoint: {
    Label = label';
    Exporter = node;
    MountPoint = mountPoint;
  };

  cpu = "AMD Ryzen 7 2700X Eight-Core Processor";
  gpu = "NVIDIA GeForce RTX 3060";
  board = "nct6798";
  nvme = "nvme";
  sandisk = "SanDisk SSD PLUS";
  peaq = "PEAQ    SSD_256G";

  # drivetemp names a disk by the first 16 characters of its model.
  hdds = {
    disk1 = "ST10000NE0008-2P";
    disk2 = "ST4000VN008-2DR1";
  };

  dataDisks = lib.sort (a: b: a < b) (lib.attrValues storage.dataDisks);
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
            (temperature "Motherboard" board "temp1")
          ]
          ++ lib.mapAttrsToList (name: model: temperature name model "temp1") hdds
          ++ [
            (temperature "SSD (SanDisk)" sandisk "temp1")
            (temperature "SSD (PEAQ)" peaq "temp1")
            (temperature "NVMe" nvme "temp1")
          ];
          Disks = [
            (disk "Bulk (${storage.bulkMount})" storage.bulkMount)
          ]
          ++ map (mountPoint: disk (baseNameOf mountPoint) mountPoint) dataDisks
          ++ [
            (disk "Fast pool" storage.fastDatasets.plex)
            (disk "NVMe (system, scratch)" "/")
            (disk "Boot" "/boot")
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
