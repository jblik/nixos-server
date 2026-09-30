{
  config,
  lib,
  pkgs,
  ...
}:
# Idle spin-down for the bulk disks.
#
# unraid did this out of the box; NixOS does not. On a box that idles most of the
# day, a media array that never spins down is the difference between ~10 W and
# ~60 W of disks, plus the noise. hd-idle watches per-device IO rather than relying
# on the drive's own (often ignored) APM timer.
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
