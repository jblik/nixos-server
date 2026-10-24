{
  config,
  lib,
  pkgs,
}:
let
  enabled = {
    keep-cool = config.host.maintenance.keepCool.enable;
    seeding = config.host.maintenance.qbittorrent.enable;
    tdarr = config.host.maintenance.tdarr.enable;
    previews = config.host.maintenance.mediaPreviewGenerator.enable;
  };
  script =
    name: path:
    pkgs.writers.writePython3 name {
      libraries = [ pkgs.python3Packages.requests ];
    } (builtins.readFile path);
  runner = script "maintenance-command" ./command.py;
in
{
  inherit script;

  command =
    task: command:
    pkgs.writeShellScript "maintenance-${task}" ''
      export MAINTENANCE_ENABLED=${lib.boolToString enabled.${task}}
      export MAINTENANCE_STATE=/var/lib/server-maintenance/${task}
      exec ${runner} ${lib.escapeShellArg command}
    '';
}
