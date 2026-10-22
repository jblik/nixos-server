{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "git.steenblik.ch";
  sshPort = 2222;
  runnerLabel = "docker:docker://ghcr.io/catthehacker/ubuntu:act-22.04";
  runnerConfig = (pkgs.formats.yaml { }).generate "forgejo-runner.yaml" {
    runner.capacity = 1;
    container = {
      docker_host = "-";
      # Docker-in-Docker services need privileged containers.
      privileged = true;
    };
  };
in
{
  config = lib.mkIf config.host.forgejo.enable {
    sops.secrets."forgejo-runner.env" = {
      restartUnits = [ "forgejo-runner-docker.service" ];
    };

    services.forgejo = {
      enable = true;
      settings = {
        server = {
          DOMAIN = domain;
          ROOT_URL = "https://${domain}/";
          HTTP_ADDR = "127.0.0.1";
          HTTP_PORT = config.host.forgejo.port;
          START_SSH_SERVER = true;
          SSH_PORT = sshPort;
          SSH_LISTEN_PORT = sshPort;
        };
        repository.DEFAULT_BRANCH = "master";
        service.DISABLE_REGISTRATION = true;
        session.COOKIE_SECURE = true;
        actions.ENABLED = true;
      };
    };

    virtualisation.podman.enable = true;

    systemd.services.forgejo-runner-docker = {
      description = "Forgejo Actions Runner";
      wantedBy = [ "multi-user.target" ];
      wants = [
        "network-online.target"
        "forgejo.service"
        "podman.socket"
      ];
      after = [
        "network-online.target"
        "forgejo.service"
        "podman.socket"
      ];
      environment = {
        DOCKER_HOST = "unix:///run/podman/podman.sock";
        HOME = "/var/lib/forgejo-runner";
      };
      serviceConfig = {
        DynamicUser = true;
        User = "forgejo-runner";
        SupplementaryGroups = [ "podman" ];
        StateDirectory = "forgejo-runner";
        RuntimeDirectory = "forgejo-runner";
        RuntimeDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/forgejo-runner";
        EnvironmentFile = config.sops.secrets."forgejo-runner.env".path;
        Restart = "always";
        RestartSec = 2;
        ExecStart = pkgs.writeShellScript "forgejo-runner-start" ''
          umask 077
          printf '%s' "$TOKEN" > "$RUNTIME_DIRECTORY/token"
          unset TOKEN
          exec ${lib.getExe pkgs.forgejo-runner} daemon \
            --config ${runnerConfig} \
            --url https://${domain}/ \
            --uuid "1488a82f-9e17-4c9e-95b2-12a46c03ae4e" \
            --token-url "file:$RUNTIME_DIRECTORY/token" \
            --label ${lib.escapeShellArg runnerLabel}
        '';
      };
    };

    networking.firewall.allowedTCPPorts = [ sshPort ];

    environment.systemPackages = [ config.services.forgejo.package ];

    # Otherwise it can run before the dataset is mounted and write a fresh secret_key underneath.
    systemd.services.forgejo-secrets.unitConfig.RequiresMountsFor = [
      config.services.forgejo.customDir
    ];

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
