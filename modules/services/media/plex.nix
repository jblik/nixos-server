{ config, lib, ... }:
{
  config = lib.mkIf config.host.media.enable {
    services.plex = {
      enable = true;
      group = "users";
      # Remote access needs 32400 reachable from outside the LAN.
      openFirewall = true;
    };
  };
}
