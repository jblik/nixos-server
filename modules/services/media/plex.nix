{
  config,
  lib,
  ...
}:
let
  inherit (config.host.storage) bulkMount;
  plexRoot = "${config.services.plex.dataDir}/Plex Media Server";
  mediaDir = "${plexRoot}/Media";
in
{
  config = lib.mkIf config.host.media.enable {
    services.plex = {
      enable = true;
      group = "users";
      # Remote access needs 32400 reachable from outside the LAN.
      openFirewall = true;
    };

    fileSystems.${mediaDir} = {
      device = "${bulkMount}/plex-media";
      fsType = "none";
      options = [
        "bind"
        "nofail"
      ];
      depends = [
        bulkMount
        config.services.plex.dataDir
      ];
    };

    systemd.services.plex.unitConfig.RequiresMountsFor = [ mediaDir ];
  };
}
