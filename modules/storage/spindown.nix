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
  bulkMounts = lib.unique (lib.attrValues cfg.dataDisks ++ map dirOf cfg.parityFiles);
  disks = lib.unique (
    lib.concatMap (
      mount: lib.optional (config.fileSystems ? ${mount}) config.fileSystems.${mount}.device
    ) bulkMounts
  );
  enabled = cfg.spinDownSeconds != null && disks != [ ];
  diskArgs = lib.concatMapStrings (d: " -a ${d} -i ${toString cfg.spinDownSeconds}") disks;
in
{
  config = lib.mkIf enabled {
    systemd.services.hd-idle = {
      description = "Spin down idle bulk-tier disks";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.hd-idle} -d -i 0${diskArgs}";
        Restart = "on-failure";
      };
    };

    # `hdparm -C /dev/sdX` reports whether a disk is spun down.
    environment.systemPackages = [ pkgs.hdparm ];
  };
}
