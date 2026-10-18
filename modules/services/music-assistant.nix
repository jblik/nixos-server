{
  config,
  lib,
  pkgs,
  inputs,
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
  disabledModules = [ "services/audio/music-assistant.nix" ];
  imports = [ "${inputs.nixpkgs-music-assistant}/nixos/modules/services/audio/music-assistant.nix" ];

  config = lib.mkIf config.host.music-assistant.enable {
    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    environment.systemPackages = [ pkgs.pulseaudio ];

    # Soloist is downloaded at runtime as a generic Linux executable.
    programs.nix-ld = {
      enable = true;
      libraries = [ pkgs.libpulseaudio ];
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

    services.music-assistant = {
      enable = true;
      providers = [
        "spotify"
        "spotify_connect"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/sendspin 0700 root root -"
      # Seed once; pairing and authentication settings remain writable in the UI.
      "C /var/lib/sendspin/config.json 0600 root root - ${bridgeConfig}"
    ];

    systemd.services = {
      music-assistant = {
        path = [ pkgs.pulseaudio ];
        # DynamicUser's private state mount otherwise prevents Soloist from executing.
        serviceConfig.ExecPaths = [ "/var/lib/music-assistant" ];
        # Spotify's audio capture and Sendspin use local Unix sockets.
        serviceConfig.RestrictAddressFamilies = [ "AF_UNIX" ];
      };
      sendspin = {
        description = "Sendspin Bluetooth bridge";
        # The bridge detects systemd and requests restarts using this upstream unit name.
        aliases = [ "sendspin-client.service" ];
        wantedBy = [ "multi-user.target" ];
        requires = [
          "bluetooth.service"
          "pipewire.service"
          "pipewire-pulse.service"
          "wireplumber.service"
        ];
        wants = [ "music-assistant.service" ];
        after = [
          "bluetooth.service"
          "pipewire.service"
          "pipewire-pulse.service"
          "wireplumber.service"
          "music-assistant.service"
        ];
        path = [
          pkgs.bluez
          pkgs.pulseaudio
          pkgs.usbutils
          pkgs.kmod
        ];
        environment = {
          TZ = config.host.timezone;
          WEB_PORT = "8098";
          BASE_LISTEN_PORT = "8928";
          CONFIG_DIR = "/var/lib/sendspin";
          PULSE_SERVER = "unix:/run/pulse/native";
          PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
        };
        serviceConfig = {
          ExecStart = lib.getExe pkgs.sendspin-bt-bridge;
          Restart = "on-failure";
          StateDirectory = "sendspin";
          StateDirectoryMode = "0700";
          SupplementaryGroups = [ "pipewire" ];
          UMask = "0077";
        };
      };
    };

    services.home-assistant.extraComponents = lib.mkIf config.host.home-assistant.enable [
      "music_assistant"
    ];

    networking.firewall.extraInputRules = ''
      ip saddr ${config.host.lanCidr} tcp dport { 8097, 8927 } accept
      # Spotify Connect chooses a new listener port from the host's ephemeral range.
      ip saddr ${config.host.lanCidr} tcp dport 32768-60999 accept
      ip saddr ${config.host.lanCidr} udp dport 5353 accept
    '';
  };
}
