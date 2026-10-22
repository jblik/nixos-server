{ config, lib, ... }:
{
  config = lib.mkIf config.host.home-assistant.enable {
    services.matter-server = {
      enable = true;
      extraArgs.listen-address = "127.0.0.1";
    };

    services.home-assistant = {
      enable = true;
      extraComponents = [
        "apple_tv"
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
