{
  config,
  lib,
  pkgs,
}:
let
  host = config.host;
  defaults = pkgs.writeText "maintenance-defaults.json" (
    builtins.toJSON {
      Window = host.maintenanceWindow;
      Tasks = {
        seeding = host.media.qbittorrent.seedingSchedule;
        tdarr = host.media.tdarr.nodeSchedule;
        previews = host.media.mediaPreviewGenerator.cpuWorkersSchedule;
      };
    }
  );
  runner = pkgs.writers.writePython3 "maintenance-command" { } (
    builtins.readFile ./maintenance-command.py
  );
in
task: command:
pkgs.writeShellScript "maintenance-${task}" ''
  export MAINTENANCE_DEFAULTS=${defaults}
  export MAINTENANCE_STATE=/var/lib/server-dashboard/keep-cool.json
  exec ${runner} ${
    lib.escapeShellArgs [
      task
      command
    ]
  }
''
