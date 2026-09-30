{ config, lib, ... }:
let
  domain = "git.steenblik.ch";
  sshPort = 2222;
in
{
  config = lib.mkIf config.host.forgejo.enable {
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
        service.DISABLE_REGISTRATION = true;
        session.COOKIE_SECURE = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ sshPort ];

    environment.systemPackages = [ config.services.forgejo.package ];

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
