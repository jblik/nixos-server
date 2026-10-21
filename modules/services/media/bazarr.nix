{ config, lib, ... }:
{
  config = lib.mkIf config.host.media.enable {
    services.bazarr = {
      enable = true;
      group = "users";
      listenPort = 6767;
    };
  };
}
