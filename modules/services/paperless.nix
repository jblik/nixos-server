{ config, lib, ... }:
let
  domain = "paperless.internal.steenblik.ch";
in
{
  config = lib.mkIf config.host.paperless.enable {
    services.paperless = {
      enable = true;
      inherit domain;
      mediaDir = "${config.host.storage.bulkMount}/documents";
      database.createLocally = true;
      configureTika = true;
    };

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
