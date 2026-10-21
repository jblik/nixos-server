{ config, lib, ... }:
{
  config = lib.mkIf config.host.media.enable {
    services.flaresolverr = {
      enable = true;
      port = 8191;
    };
  };
}
