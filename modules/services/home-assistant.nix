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
