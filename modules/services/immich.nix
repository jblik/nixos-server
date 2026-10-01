{
  config,
  lib,
  pkgs-unstable,
  ...
}:
let
  inherit (config.host.storage) bulkMount;
  mediaLocation = "${bulkMount}/photos";
in
{
  config = lib.mkIf config.host.immich.enable {
    services.immich = {
      enable = true;
      # 26.05 only has the end-of-life 2.x, marked insecure; 3.x needs the same vectorchord.
      package = pkgs-unstable.immich;
      inherit mediaLocation;
    };

    systemd.tmpfiles.rules = [ "d ${mediaLocation} 0700 immich immich -" ];

    systemd.services.immich-server.unitConfig.RequiresMountsFor = [ bulkMount ];

    services.nginx.virtualHosts."immich.internal.steenblik.ch".extraConfig = ''
      client_max_body_size 50000M;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
    '';
  };
}
