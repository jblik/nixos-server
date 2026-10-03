{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.host.media.enable {
    services.plex = {
      enable = true;
      group = "users";
      # Remote access needs 32400 reachable from outside the LAN.
      openFirewall = true;
    };

    # Not a StateDirectory, so nothing else stops Plex from running without its dataset.
    systemd.services.plex.unitConfig.RequiresMountsFor = [ config.services.plex.dataDir ];
  };
}
