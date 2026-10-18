{
  config,
  lib,
  pkgs,
  ...
}:
let
  bridgeConfig = pkgs.writeText "sendspin-config.json" (
    builtins.toJSON {
      SENDSPIN_SERVER = "127.0.0.1";
      SENDSPIN_PORT = 8927;
      MA_API_URL = "http://127.0.0.1:8095";
      TZ = config.host.timezone;
    }
  );
in
{
  config = lib.mkIf config.host.music-assistant.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    services.pipewire = {
      enable = true;
      systemWide = true;
      pulse.enable = true;
      wireplumber.extraConfig."99-headless-bluetooth" = {
        # A server has no active graphical seat to grant Bluetooth audio access.
        "wireplumber.profiles".main."monitor.bluez.seat-monitoring" = "disabled";
      };
    };

    virtualisation.podman.enable = true;
    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        music-assistant = {
          image = "ghcr.io/music-assistant/server:2.10.7";
          environment.TZ = config.host.timezone;
          volumes = [ "/var/lib/music-assistant:/data" ];
          extraOptions = [ "--network=host" ];
        };
        sendspin = {
          image = "ghcr.io/trudenboy/sendspin-bt-bridge:2.76.4";
          environment = {
            TZ = config.host.timezone;
            WEB_PORT = "8098";
            BASE_LISTEN_PORT = "8928";
            CONFIG_DIR = "/config";
            PULSE_SERVER = "unix:/run/pulse/native";
            PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
          };
          volumes = [
            "/var/lib/sendspin:/config"
            "/run/dbus:/var/run/dbus:ro"
            "/run/pulse:/run/pulse:ro"
            "/run/pipewire:/run/pipewire:ro"
          ];
          extraOptions = [
            "--network=host"
            "--cap-add=NET_ADMIN"
            "--cap-add=NET_RAW"
            "--group-add=${toString config.ids.gids.pipewire}"
          ];
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/music-assistant 0700 root root -"
      "d /var/lib/sendspin 0700 root root -"
      # Seed once; pairing and authentication settings remain writable in the UI.
      "C /var/lib/sendspin/config.json 0600 root root - ${bridgeConfig}"
    ];

    systemd.services = {
      podman-music-assistant.unitConfig.RequiresMountsFor = [ "/var/lib/music-assistant" ];
      podman-sendspin = {
        requires = [
          "bluetooth.service"
          "pipewire.service"
          "pipewire-pulse.service"
          "wireplumber.service"
        ];
        wants = [ "podman-music-assistant.service" ];
        after = [
          "bluetooth.service"
          "pipewire.service"
          "pipewire-pulse.service"
          "wireplumber.service"
          "podman-music-assistant.service"
        ];
        unitConfig.RequiresMountsFor = [ "/var/lib/sendspin" ];
      };
    };

    services.home-assistant.extraComponents = lib.mkIf config.host.home-assistant.enable [
      "music_assistant"
    ];

    networking.firewall.extraInputRules = ''
      ip saddr ${config.host.lanCidr} tcp dport { 8097, 8927 } accept
      ip saddr ${config.host.lanCidr} udp dport 5353 accept
    '';
  };
}
