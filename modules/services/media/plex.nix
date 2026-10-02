{
  config,
  lib,
  pkgs-unstable,
  ...
}:
{
  config = lib.mkIf config.host.media.enable {
    services.plex = {
      enable = true;
      # Not older than unraid's, whose database gets imported; a downgrade can't open it.
      package = pkgs-unstable.plex;
      group = "users";
      # Remote access needs 32400 reachable from outside the LAN.
      openFirewall = true;
    };
  };
}
