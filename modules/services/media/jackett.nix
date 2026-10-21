{ config, lib, ... }:
{
  config = lib.mkIf config.host.media.enable {
    services.jackett = {
      enable = true;
      port = 9117;
    };

    # Not a StateDirectory, so nothing else stops Jackett from running without its dataset.
    systemd.services.jackett.unitConfig.RequiresMountsFor = [ config.services.jackett.dataDir ];
  };
}
