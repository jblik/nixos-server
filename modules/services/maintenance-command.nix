{
  config,
  lib,
  pkgs,
}:
let
  host = config.host;
  defaults = pkgs.writeText "maintenance-defaults.json" (
    builtins.toJSON {
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
  ${lib.optionalString host.dashboard.enable ''
    export MAINTENANCE_URL=http://127.0.0.1:${toString config.services.server-dashboard.internalPort}/maintenance-windows
  ''}
  exec ${runner} ${
    lib.escapeShellArgs [
      task
      command
    ]
  }
''
