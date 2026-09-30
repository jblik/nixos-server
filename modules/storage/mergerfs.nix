{
  config,
  lib,
  pkgs,
  ...
}:
# Bulk tier, part 1: union the per-disk filesystems into one tree.
#
# Each data disk is its own XFS filesystem mounted at /mnt/diskN. mergerfs presents
# them as a single directory at `host.storage.bulkMount`, so services see one big
# filesystem while the disks stay independent — mixed sizes, add one whenever, spin
# down separately, and losing a disk loses only that disk's files.
#
# Parity is a separate concern, handled in snapraid.nix.
let
  cfg = config.host.storage;
  branches = lib.attrValues cfg.dataDisks;
  enabled = branches != [ ];
in
{
  config = lib.mkIf enabled {
    # Puts mount.fuse.mergerfs on the path the mount units use.
    system.fsPackages = [ pkgs.mergerfs ];
    environment.systemPackages = [ pkgs.mergerfs ];

    fileSystems.${cfg.bulkMount} = {
      # mergerfs takes its branches as a colon-separated device string.
      device = lib.concatStringsSep ":" branches;
      fsType = "fuse.mergerfs";
      options = cfg.mergerfsOptions ++ [
        # Do not block boot on the union; the branches are mounted first.
        "nofail"
        "x-systemd.device-timeout=5s"
      ];
      # Every branch must be mounted before the union is assembled, otherwise
      # mergerfs happily unions empty mountpoints and services write into the
      # root filesystem instead of the array.
      depends = branches;
    };
  };
}
