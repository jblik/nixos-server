{ config, lib, ... }:
# Fast tier: a ZFS mirror holding everything small, hot and constantly changing —
# service state, PostgreSQL (immich, paperless), Redis and GGUF models.
#
# ZFS is used *here* and deliberately not for the bulk array: it buys checksums,
# atomic snapshots and `zfs send` replication, which matter for live databases and
# do not fit an array of mixed-size disks that should spin down independently.
#
# The pool itself is created once by hand (it cannot be declared) — see the
# `host.storage.fastPool` description. This module only manages it afterwards.
let
  inherit (config.host.storage) fastPool hostId;
  enabled = fastPool != null;
in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = hostId != null;
        message = ''
          host.storage.hostId must be set when host.storage.fastPool is used:
          ZFS needs it to notice a pool that was last imported by another system.
          Generate one with `head -c 8 /etc/machine-id`.
        '';
      }
    ];

    networking.hostId = hostId;
    boot.supportedFilesystems = [ "zfs" ];

    # The NVIDIA driver and ZFS both build against the kernel; if a rebuild ever
    # fails on one of them, pin boot.kernelPackages to a version both support.
    boot.zfs.forceImportRoot = false;

    services.zfs = {
      autoScrub = {
        enable = true;
        interval = "monthly";
      };
      # SSD mirror: keep it trimmed.
      trim.enable = true;
    };

    # Snapshots, so a bad nixos-rebuild or a botched service upgrade is a
    # rollback rather than an incident. Off-box replication (services.syncoid) is
    # still to do (docs/MIGRATION.md, step 4).
    services.sanoid = {
      enable = true;
      datasets."${fastPool}" = {
        recursive = true;
        autoprune = true;
        autosnap = true;
        hourly = 24;
        daily = 14;
        monthly = 3;
        yearly = 0;
      };
    };
  };
}
