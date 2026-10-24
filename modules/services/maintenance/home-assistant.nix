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
      name = "Keep cool";
      unit = "coolercontrol-maintenance.service";
      settings = host.maintenance.keepCool;
    }
  ]
  ++ lib.optionals host.media.enable [
    {
      id = "seeding";
      state = "seeding";
      name = "qBittorrent seeding";
      unit = "qbittorrent-seeding-schedule.service";
      settings = host.maintenance.qbittorrent;
    }
    {
      id = "tdarr";
      state = "tdarr";
      name = "Tdarr node";
      unit = "tdarr-maintenance.service";
      settings = host.maintenance.tdarr;
    }
    {
      id = "previews";
      state = "previews";
      name = "Preview CPU workers";
      unit = "previews-maintenance.service";
      settings = host.maintenance.mediaPreviewGenerator;
    }
  ];
  timeHelpers =
    name: label: window:
    lib.mapAttrs' (edge: value: lib.nameValuePair "server_maintenance_${name}${edge}" value) (
      lib.genAttrs [ "start" "end" ] (edge: {
        name = "${label} ${edge}";
        has_date = false;
        has_time = true;
        initial = "${window.${edge}}:00";
      })
    );
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
  active = task: ''
    {% set shared = is_state('input_boolean.server_maintenance_${task.id}_inherit', 'on') %}
    {% set prefix = 'input_datetime.server_maintenance_' ~ ("" if shared else '${task.id}_') %}
    {% set start = states(prefix ~ 'start') %}
    {% set end = states(prefix ~ 'end') %}
    {% set time = now().strftime('%H:%M:%S') %}
    {% set scheduled = (start <= time < end) if start <= end else (time >= start or time < end) %}
    {{ ${lib.boolToString task.settings.enable} and
       (is_state('input_boolean.server_maintenance', 'on') or
        (is_state('input_boolean.server_maintenance_schedule', 'on') and scheduled)) }}
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
        input_boolean = {
          server_maintenance = {
            name = "Server maintenance";
            icon = "mdi:tools";
          };
          server_maintenance_schedule = {
            name = "Server maintenance schedule";
            initial = true;
            icon = "mdi:calendar-clock";
          };
        }
        // builtins.listToAttrs (
          map (
            task:
            lib.nameValuePair "server_maintenance_${task.id}_inherit" {
              name = "${task.name}: use shared maintenance window";
              initial = task.settings.window == host.maintenance.window;
            }
          ) tasks
        );

        input_datetime =
          timeHelpers "" "Server maintenance" host.maintenance.window
          // lib.foldl' (
            helpers: task: helpers // timeHelpers "${task.id}_" task.name task.settings.window
          ) { } tasks;

        shell_command = builtins.listToAttrs (
          map (
            task: lib.nameValuePair "server_maintenance_${task.id}" "${apply task} {{ active | lower }}"
          ) tasks
        );

        "automation maintenance" = map (task: {
          id = "server_maintenance_${task.id}";
          alias = "Server maintenance: ${task.name}";
          mode = "queued";
          triggers = [
            {
              trigger = "homeassistant";
              event = "start";
            }
            {
              trigger = "state";
              entity_id = [
                "input_boolean.server_maintenance"
                "input_boolean.server_maintenance_schedule"
                "input_boolean.server_maintenance_${task.id}_inherit"
                "input_datetime.server_maintenance_start"
                "input_datetime.server_maintenance_end"
                "input_datetime.server_maintenance_${task.id}_start"
                "input_datetime.server_maintenance_${task.id}_end"
              ];
            }
            {
              trigger = "time";
              at = [
                "input_datetime.server_maintenance_start"
                "input_datetime.server_maintenance_end"
                "input_datetime.server_maintenance_${task.id}_start"
                "input_datetime.server_maintenance_${task.id}_end"
              ];
            }
          ];
          actions = [
            {
              action = "shell_command.server_maintenance_${task.id}";
              data.active = active task;
            }
          ];
        }) tasks;
      };
    };
  };
}
