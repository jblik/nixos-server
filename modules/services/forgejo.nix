{ config, lib, ... }:
# Forgejo at https://git.steenblik.ch, behind nginx (proxy.nix). Git over SSH goes
# through the system sshd as the `forgejo` user.
let
  domain = "git.steenblik.ch";
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
        };
        # Publicly reachable: accounts are created by hand (docs/MIGRATION.md).
        service.DISABLE_REGISTRATION = true;
        session.COOKIE_SECURE = true;
      };
    };

    environment.systemPackages = [ config.services.forgejo.package ];

    # nginx's default 10M limit rejects larger git pushes over HTTPS.
    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
