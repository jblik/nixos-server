{
  config,
  lib,
  pkgs,
  ...
}:
# Idle spin-down for the bulk disks.
#
# hd-idle watches per-device IO rather than relying on the drive's own APM timer.
#
# Do not point this at SSDs.
let
  cfg = config.host.storage;
  enabled = cfg.spinDownSeconds != null && cfg.dataDisks != { };
in
{
  config = lib.mkIf enabled {
    systemd.services.hd-idle = {
      description = "Spin down idle bulk-tier disks";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.hd-idle} -d -i ${toString cfg.spinDownSeconds}";
        Restart = "on-failure";
      };
    };

    # `hdparm -C /dev/sdX` reports whether a disk is spun down.
    environment.systemPackages = [ pkgs.hdparm ];
  };
}
