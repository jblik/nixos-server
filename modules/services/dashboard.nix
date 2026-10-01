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

  exporter = "node";

  label = name: value: {
    Name = name;
    Value = value;
  };

  # Same sensors fan2go drives the fans from (modules/hardware/fans.nix); node_exporter names
  # a hwmon chip after its sysfs device path.
  cpuChip = "pci0000:00_0000:00:18_3";
  fanChip = "platform_nct6775_656";

  fan = channel: {
    Label = "Fan ${toString channel}";
    Exporter = exporter;
    Metric = "node_hwmon_fan_rpm";
    Labels = [
      (label "chip" fanChip)
      (label "sensor" "fan${toString channel}")
    ];
  };
in
{
  imports = [ inputs.server-dashboard.nixosModules.default ];

  config = lib.mkIf host.dashboard.enable {
    services.prometheus.exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
    };

    services.server-dashboard = {
      enable = true;
      settings.Dashboard = {
        Services = services;
        Metrics = {
          Exporters = [
            {
              Name = exporter;
              Url = "http://127.0.0.1:${toString config.services.prometheus.exporters.node.port}/metrics";
            }
          ];
          Temperatures = [
            {
              # Tdie; temp1 is Tctl, which carries a +10 °C offset on the 2700X.
              Label = "CPU";
              Exporter = exporter;
              Metric = "node_hwmon_temp_celsius";
              Labels = [
                (label "chip" cpuChip)
                (label "sensor" "temp2")
              ];
            }
          ];
          Disks = [
            {
              Label = "Bulk (/data)";
              Exporter = exporter;
              MountPoint = host.storage.bulkMount;
            }
            {
              Label = "Fast pool";
              Exporter = exporter;
              MountPoint = host.storage.fastDatasets.plex;
            }
            {
              Label = "NVMe (system, scratch)";
              Exporter = exporter;
              MountPoint = "/";
            }
          ];
          Fans = map fan (lib.range 1 7);
        };
      };
    };
  };
}
