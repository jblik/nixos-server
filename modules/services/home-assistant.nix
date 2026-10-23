{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.host.home-assistant.enable {
    sops.secrets.apple-username = {
      owner = "hass";
      restartUnits = [ "home-assistant.service" ];
    };
    sops.secrets.apple-token = {
      owner = "hass";
      restartUnits = [ "home-assistant.service" ];
    };

    services.matter-server = {
      enable = true;
      extraArgs.listen-address = "127.0.0.1";
    };

    services.home-assistant = {
      enable = true;
      customComponents = with pkgs.home-assistant-custom-components; [
        flightradar24
        mass-queue
      ];
      customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
        atomic-calendar-revive
        flightradar24
        kiosk-mode
        mass-player-card
      ];
      extraComponents = [
        "apple_tv"
        "caldav"
        "default_config"
        "homekit_controller"
        "hue"
        "matter"
        "ollama"
        "plex"
        "roborock"
        "swiss_public_transport"
        "switchbot"
      ];
      config = {
        default_config = { };
        automation = "!include automations.yaml";
        "automation chromebook" = [
          {
            id = "chromebook_wake_when_room_is_bright";
            alias = "Chromebook: wake when room is bright";
            triggers = [
              {
                trigger = "numeric_state";
                entity_id = "sensor.chromebook_tablet_light_sensor";
                above = 20;
                "for" = "00:00:05";
              }
              {
                trigger = "homeassistant";
                event = "start";
              }
            ];
            conditions = [
              {
                condition = "numeric_state";
                entity_id = "sensor.chromebook_tablet_light_sensor";
                above = 20;
              }
            ];
            actions = [ { action = "script.chromebook_wake"; } ];
          }
          {
            id = "chromebook_sleep_when_room_is_dark";
            alias = "Chromebook: sleep when room is dark";
            triggers = [
              {
                trigger = "numeric_state";
                entity_id = "sensor.chromebook_tablet_light_sensor";
                below = 10;
                "for" = "00:01:00";
              }
              {
                trigger = "homeassistant";
                event = "start";
              }
            ];
            conditions = [
              {
                condition = "numeric_state";
                entity_id = "sensor.chromebook_tablet_light_sensor";
                below = 10;
              }
            ];
            actions = [ { action = "script.chromebook_sleep"; } ];
          }
        ];
        script = {
          chromebook_wake = {
            alias = "Chromebook: wake";
            sequence = [
              {
                action = "notify.mobile_app_chromebook_tablet";
                data = {
                  message = "command_screen_on";
                  data.command = "keep_screen_on";
                };
              }
            ];
          };
          chromebook_sleep = {
            alias = "Chromebook: sleep";
            sequence = [
              {
                action = "notify.mobile_app_chromebook_tablet";
                data = {
                  message = "command_screen_off_timeout";
                  data.command = 30000;
                };
              }
              {
                action = "notify.mobile_app_chromebook_tablet";
                data = {
                  # An absent command leaves keep-screen-on unchanged in the Android app.
                  message = "command_screen_on";
                  data.command = "turn_off";
                };
              }
            ];
          };
        };
        calendar = [
          {
            platform = "caldav";
            url = "https://caldav.icloud.com/";
            username = "!include ${config.sops.secrets.apple-username.path}";
            password = "!include ${config.sops.secrets.apple-token.path}";
          }
        ];
        homeassistant.time_zone = config.host.timezone;
        http = {
          server_port = config.host.home-assistant.port;
          use_x_forwarded_for = true;
          trusted_proxies = [ "127.0.0.1" ];
        };
        homekit = [
          {
            name = "Home Assistant";
            port = config.host.home-assistant.homekitPort;
            filter.include_domains = [
              "button.rocky_all_but_shower"
              "button.button.rocky_kitchen"
              "light"
              "sensor"
              "vacuum"
            ];
          }
        ];
      };
    };

    networking.firewall.extraInputRules = ''
      ip saddr ${config.host.lanCidr} tcp dport { ${toString config.services.home-assistant.config.http.server_port}, ${toString config.host.home-assistant.homekitPort} } accept
      ip saddr ${config.host.lanCidr} udp dport { ${toString config.host.networking.mdnsPort}, ${toString config.host.home-assistant.matterPort} } accept
    '';
  };
}
