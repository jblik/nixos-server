{
  config,
  lib,
  pkgs,
  ...
}:
let
  host = config.host;
  tasks = [
    {
      id = "keep_cool";
      state = "keep-cool";
      unit = "coolercontrol-maintenance.service";
    }
  ]
  ++ lib.optionals host.media.enable [
    {
      id = "seeding";
      state = "seeding";
      unit = "qbittorrent-seeding-schedule.service";
    }
    {
      id = "tdarr";
      state = "tdarr";
      unit = "tdarr-maintenance.service";
    }
    {
      id = "previews";
      state = "previews";
      unit = "previews-maintenance.service";
    }
  ];
  apply =
    task:
    pkgs.writeShellScript "maintenance-${task.id}-set" ''
      set -eu
      case "$1" in true|false) ;; *) exit 1 ;; esac
      umask 022
      printf '%s\n' "$1" > /var/lib/server-maintenance/${task.state}.tmp
      ${pkgs.coreutils}/bin/mv /var/lib/server-maintenance/${task.state}.tmp /var/lib/server-maintenance/${task.state}
      exec ${pkgs.systemd}/bin/systemctl start ${task.unit}
    '';
in
{
  config = lib.mkIf host.home-assistant.enable {
    systemd.services.home-assistant.serviceConfig.ReadWritePaths = [ "/var/lib/server-maintenance" ];

    systemd.tmpfiles.rules = [ "d /var/lib/server-maintenance 0755 hass hass -" ];

    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            ${builtins.toJSON (map (task: task.unit) tasks)}.indexOf(action.lookup("unit")) !== -1 &&
            action.lookup("verb") == "start" && subject.user == "hass") {
          return polkit.Result.YES;
        }
      });
    '';

    services.home-assistant = {
      extraComponents = [ "shell_command" ];
      config = {
        input_boolean.server_maintenance = {
          name = "Server maintenance";
          icon = "mdi:tools";
        };

        shell_command = builtins.listToAttrs (
          map (
            task: lib.nameValuePair "server_maintenance_${task.id}" "${apply task} {{ active | lower }}"
          ) tasks
        );
      };
    };
  };
}
