{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "git.steenblik.ch";
  sshPort = 2222;
in
{
  config = lib.mkIf config.host.forgejo.enable {
    sops.secrets."forgejo-runner.env" = {
      restartUnits = [ "gitea-runner-docker.service" ];
    };

    services.forgejo = {
      enable = true;
      settings = {
        server = {
          DOMAIN = domain;
          ROOT_URL = "https://${domain}/";
          HTTP_ADDR = "127.0.0.1";
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

    services.gitea-actions-runner = {
      package = pkgs.forgejo-runner;
      instances.docker = {
        enable = true;
        name = "${config.networking.hostName}-docker";
        url = "https://${domain}/";
        tokenFile = config.sops.secrets."forgejo-runner.env".path;
        labels = [
          "docker:docker://ghcr.io/catthehacker/ubuntu:act-22.04"
        ];
        settings = {
          runner.capacity = 1;
          container = {
            docker_host = "-";
            # Docker-in-Docker services need privileged containers.
            privileged = true;
          };
        };
      };
    };

    systemd.services.gitea-runner-docker = {
      wants = [
        "forgejo.service"
        "podman.socket"
      ];
      after = [
        "forgejo.service"
        "podman.socket"
      ];
      serviceConfig.Restart = lib.mkForce "always";
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
