{
  config,
  lib,
  inputs,
  ...
}:
# server.steenblik.ch shows the public services to everyone; from the LAN or tailnet the
# page also loads server.internal.steenblik.ch, which adds the internal services and the
# metrics node_exporter reports (temperatures, free space, fan speeds, internet speed).
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
  zfs = "zfs";
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
  # A spun-down Hdd reads 0 °C (drivetemp_suspend in modules/hardware/fans.nix).
  temperature =
    part:
    reading "temperature_celsius" "sensor" part.name part.device part.sensor // { Kind = part.kind; };
  fan = reading "fan_rpm" "channel";

  disk = label': mountPoint: {
    Label = label';
    Exporter = node;
    MountPoint = mountPoint;
  };
  # The pool's datasets each report only their own data as used, so the whole pool is read
  # from zfs_exporter instead.
  pool = label': name: {
    Label = label';
    Exporter = zfs;
    Pool = name;
  };

  sensors = lib.attrValues host.sensors;
  board = host.sensors.motherboard.device;
  gpu = host.sensors.gpu.device;

  kinds = [
    "Cpu"
    "Gpu"
    "Board"
    "Nvme"
    "Ssd"
    "Hdd"
  ];

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

    services.prometheus.exporters.zfs = lib.mkIf (storage.fastPool != null) {
      enable = true;
      listenAddress = "127.0.0.1";
      pools = [ storage.fastPool ];
    };

    systemd.services.server-dashboard = {
      wants = [ "coolercontrol-defaults.service" ];
      after = [ "coolercontrol-defaults.service" ];
      serviceConfig.LoadCredential = "${tokenCredential}:/var/lib/coolercontrol-defaults/dashboard-token";
    };

    # The dashboard's run button; DynamicUser names the user after the unit.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "speedtest.service" &&
            action.lookup("verb") == "start" &&
            subject.user == "server-dashboard") {
          return polkit.Result.YES;
        }
      });
    '';

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
          ]
          ++ lib.optionals (storage.fastPool != null) [
            {
              Name = zfs;
              Url = "http://127.0.0.1:${toString config.services.prometheus.exporters.zfs.port}/metrics";
            }
          ];
          FanControl = coolercontrol;
          # Written by modules/services/speedtest.nix.
          Speedtest = node;
          SpeedtestUnit = "speedtest.service";
          Temperatures = lib.concatMap (
            kind: map temperature (lib.filter (part: part.kind == kind) sensors)
          ) kinds;
          Disks = [
            (disk "Bulk (${storage.bulkMount})" storage.bulkMount)
          ]
          ++ map (mountPoint: disk (baseNameOf mountPoint) mountPoint) dataDisks
          ++ lib.optionals (storage.fastPool != null) [ (pool "Fast pool" storage.fastPool) ]
          ++ [
            (disk "NVMe (system, scratch)" "/")
            (disk "Boot" "/boot")
          ];
          Fans = [
            (fan "Front 1" board "fan1")
            (fan "Front 2" board "fan4")
            (fan "Front 3" board "fan3")
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
