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
        homeassistant.time_zone = config.host.timezone;
        http = {
          server_port = 8123;
          use_x_forwarded_for = true;
          trusted_proxies = [ "127.0.0.1" ];
        };
        homekit = [
          {
            name = "Home Assistant";
            port = 21063;
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
      ip saddr ${config.host.lanCidr} tcp dport { 8123, 21063 } accept
      ip saddr ${config.host.lanCidr} udp dport { 5353, 5540 } accept
    '';
  };
}
