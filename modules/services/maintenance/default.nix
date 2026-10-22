{
  config,
  lib,
  pkgs,
}:
let
  host = config.host;
  taskDefaults = task: task.window // { enabled = task.enable; };
  defaults = pkgs.writeText "maintenance-defaults.json" (
    builtins.toJSON {
      Tasks = {
        keep-cool = taskDefaults host.maintenance.keepCool;
        seeding = taskDefaults host.maintenance.qbittorrent;
        tdarr = taskDefaults host.maintenance.tdarr;
        previews = taskDefaults host.maintenance.mediaPreviewGenerator;
      };
    }
  );
  pythonModule = pkgs.python3Packages.toPythonModule (
    pkgs.runCommand "maintenance-python" { propagatedBuildInputs = [ ]; } ''
      install -Dm644 ${./window.py} "$out/${pkgs.python3.sitePackages}/maintenance.py"
    ''
  );
  script =
    name: path:
    pkgs.writers.writePython3 name {
      libraries = [
        pkgs.python3Packages.requests
        pythonModule
      ];
    } (builtins.readFile path);
  runner = script "maintenance-command" ./command.py;
in
{
  inherit script;

  command =
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
    '';
}
