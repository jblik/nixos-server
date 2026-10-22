{
  config,
  lib,
  pkgs,
  ...
}:
let
  maintenanceCommand = import ../maintenance-command.nix { inherit config lib pkgs; };
  workerSchedule = pkgs.writers.writePython3 "media-worker-schedule" {
    libraries = [ pkgs.python3Packages.requests ];
  } (builtins.readFile ./worker-schedule.py);
in
{
  config = lib.mkIf config.host.media.enable {
    systemd.services = lib.genAttrs [ "tdarr-maintenance" "previews-maintenance" ] (
      name:
      let
        tdarr = name == "tdarr-maintenance";
      in
      {
        description = "Apply the ${
          if tdarr then "Tdarr node" else "preview CPU worker"
        } maintenance window";
        wantedBy = [
          (if tdarr then "tdarr-node-main.service" else "podman-media-preview-generator.service")
        ];
        after = [ (if tdarr then "tdarr-node-main.service" else "podman-media-preview-generator.service") ];
        partOf = [
          (if tdarr then "tdarr-node-main.service" else "podman-media-preview-generator.service")
        ];
        environment = {
          TASK = if tdarr then "tdarr" else "previews";
          TDARR_URL = "http://127.0.0.1:${toString config.services.tdarr.server.serverPort}";
          TDARR_NODE = config.services.tdarr.nodes.main.name;
          PREVIEWS_URL = "http://127.0.0.1:${toString config.host.media.mediaPreviewGenerator.port}";
          PREVIEWS_AUTH = "/var/lib/media-preview-generator/auth.json";
          PREVIEWS_CPU_WORKERS = toString config.host.media.mediaPreviewGenerator.cpuWorkers;
          TZ = config.time.timeZone;
        };
        serviceConfig = {
          Type = "oneshot";
          Restart = "on-failure";
          RestartSec = "10s";
          ExecStart = maintenanceCommand (if tdarr then "tdarr" else "previews") workerSchedule;
        };
      }
    );
  };
}
