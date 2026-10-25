{
  config,
  lib,
  pkgs,
  ...
}:
let
  routes = [
    {
      id = "sophie_work";
      name = "Sophie Work";
      calendar = "calendar.sophie";
      match = "work";
      travelMinutes = 20;
    }
    {
      id = "jacob_work";
      name = "Jacob Work";
      calendar = "calendar.jacob";
      match = "work";
      travelMinutes = 60;
    }
    {
      id = "jacob_uni";
      name = "Jacob Uni";
      calendar = "calendar.jacob";
      match = "uni";
      travelMinutes = 60;
    }
  ];
in
{
  imports = [ ./maintenance/home-assistant.nix ];

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
        browser-mod
        flightradar24
        mass-queue
        meteoswiss
        roborock_custom_map
      ];
      customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
        atomic-calendar-revive
        card-mod
        flightradar24
        kiosk-mode
        mass-player-card
        meteoswiss-card
        xiaomi-vacuum-map-card
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
        template = map (route: {
          triggers = [
            {
              trigger = "time_pattern";
              minutes = "/1";
            }
            {
              trigger = "homeassistant";
              event = "start";
            }
          ];
          actions = [
            {
              action = "calendar.get_events";
              target.entity_id = route.calendar;
              data.duration.hours = 3;
              response_variable = "agenda";
            }
            {
              variables.event_start = ''
                {% set ns = namespace(start=none, timestamp=none) %}
                {% for event in agenda['${route.calendar}']['events'] %}
                  {% set start = as_timestamp(event.start) %}
                  {% if event.start | length > 10
                      and '${route.match}' in event.summary | lower
                      and as_timestamp(now()) < start <= as_timestamp(now()) + 10800
                      and (ns.timestamp is none or start < ns.timestamp) %}
                    {% set ns.start = event.start %}
                    {% set ns.timestamp = start %}
                  {% endif %}
                {% endfor %}
                {{ ns.start }}
              '';
            }
          ];
          binary_sensor = [
            {
              name = "${route.name} commute";
              unique_id = "${route.id}_commute";
              default_entity_id = "binary_sensor.${route.id}_commute";
              state = "{{ 0 < as_timestamp(event_start, 0) - as_timestamp(now()) <= 10800 }}";
              attributes = {
                event_start = "{{ event_start }}";
                leave_by = "{{ (as_datetime(event_start) - timedelta(minutes=${toString route.travelMinutes})).isoformat() if event_start is not none else none }}";
              };
            }
          ];
        }) routes;
        "automation commute" = map (route: {
          id = "${route.id}_commute_poll";
          alias = "${route.name}: refresh commute before event";
          triggers = [
            {
              trigger = "time_pattern";
              minutes = "/10";
            }
            {
              trigger = "state";
              entity_id = "binary_sensor.${route.id}_commute";
              to = "on";
            }
          ];
          conditions = [
            {
              condition = "state";
              entity_id = "binary_sensor.${route.id}_commute";
              state = "on";
            }
            {
              condition = "template";
              value_template = "{{ 0 < as_timestamp(state_attr('binary_sensor.${route.id}_commute', 'event_start'), 0) - as_timestamp(now()) <= 10800 }}";
            }
            {
              condition = "template";
              value_template = "{{ as_timestamp(now()) - as_timestamp(this.attributes.last_triggered, 0) >= 600 }}";
            }
          ];
          actions = [
            {
              action = "homeassistant.update_entity";
              target.entity_id = "sensor.${route.id}_departure";
            }
          ];
        }) routes;
        "automation station departures" = [
          {
            id = "station_departures_poll";
            alias = "Station: refresh departures";
            triggers = [
              {
                trigger = "time_pattern";
                minutes = "/2";
              }
              {
                trigger = "homeassistant";
                event = "start";
              }
            ];
            actions = [
              {
                action = "homeassistant.update_entity";
                target.entity_id = "sensor.station_departure";
              }
            ];
          }
        ];
        "automation chromebook" = [
          {
            id = "chromebook_wake_when_room_is_bright";
            alias = "Chromebook: wake when room is bright";
            triggers = [
              {
                trigger = "numeric_state";
                entity_id = "sensor.chromebook_tablet_light_sensor";
                above = 15;
                "for" = "00:00:02";
              }
              {
                trigger = "state";
                entity_id = "light.monkey";
                to = "on";
              }
              {
                trigger = "state";
                entity_id = [
                  "device_tracker.not_connected"
                  "device_tracker.dumbo"
                ];
                to = "home";
              }
              {
                trigger = "homeassistant";
                event = "start";
              }
            ];
            conditions = [
              {
                condition = "or";
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.monkey";
                    state = "on";
                  }
                  {
                    condition = "and";
                    conditions = [
                      {
                        condition = "template";
                        value_template = "{{ is_state('device_tracker.not_connected', 'home') or is_state('device_tracker.dumbo', 'home') }}";
                      }
                      {
                        condition = "numeric_state";
                        entity_id = "sensor.chromebook_tablet_light_sensor";
                        above = 15;
                      }
                    ];
                  }
                ];
              }
            ];
            actions = [ { action = "script.chromebook_wake"; } ];
          }
          {
            id = "chromebook_sleep_when_room_is_dark";
            alias = "Chromebook: sleep when away or room is dark";
            triggers = [
              {
                trigger = "numeric_state";
                entity_id = "sensor.chromebook_tablet_light_sensor";
                below = 10;
                "for" = "00:00:10";
              }
              {
                trigger = "state";
                entity_id = "light.monkey";
                to = "off";
              }
              {
                trigger = "template";
                value_template = "{{ not is_state('device_tracker.not_connected', 'home') and not is_state('device_tracker.dumbo', 'home') }}";
              }
              {
                trigger = "homeassistant";
                event = "start";
              }
            ];
            conditions = [
              {
                condition = "not";
                conditions = [
                  {
                    condition = "state";
                    entity_id = "light.monkey";
                    state = "on";
                  }
                ];
              }
              {
                condition = "or";
                conditions = [
                  {
                    condition = "template";
                    value_template = "{{ not is_state('device_tracker.not_connected', 'home') and not is_state('device_tracker.dumbo', 'home') }}";
                  }
                  {
                    condition = "numeric_state";
                    entity_id = "sensor.chromebook_tablet_light_sensor";
                    below = 10;
                  }
                ];
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
              {
                action = "notify.mobile_app_chromebook_tablet";
                data = {
                  message = "command_screen_brightness_level";
                  data.command = 255;
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
                  message = "command_screen_on";
                  data.command = "keep_screen_on";
                };
              }
              {
                action = "notify.mobile_app_chromebook_tablet";
                data = {
                  message = "command_screen_brightness_level";
                  data.command = 0;
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
