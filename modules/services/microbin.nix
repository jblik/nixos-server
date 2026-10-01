{ config, lib, ... }:
let
  domain = "notes.steenblik.ch";
in
{
  config = lib.mkIf config.host.microbin.enable {
    sops.secrets."microbin.env" = { };

    services.microbin = {
      enable = true;
      passwordFile = config.sops.secrets."microbin.env".path;
      settings = {
        MICROBIN_BIND = "127.0.0.1";
        MICROBIN_PORT = config.host.microbin.port;
        MICROBIN_PUBLIC_PATH = "https://${domain}/";
        MICROBIN_TITLE = "Notes";
        MICROBIN_PRIVATE = true;
        MICROBIN_NO_LISTING = true;
        MICROBIN_QR = true;
        MICROBIN_ENABLE_BURN_AFTER = true;
        MICROBIN_DEFAULT_EXPIRY = "24hour";
        MICROBIN_GC_DAYS = 90;
        MICROBIN_HIDE_HEADER = true;
        MICROBIN_HIDE_FOOTER = true;
        MICROBIN_ENCRYPTION_CLIENT_SIDE = false;
        MICROBIN_ENCRYPTION_SERVER_SIDE = false;
        MICROBIN_DISABLE_TELEMETRY = true;
      };
    };

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 256M;
    '';
  };
}
