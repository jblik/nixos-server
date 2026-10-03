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
  inherit (config.host.storage) fastPool fastDatasets hostId;
  enabled = fastPool != null;
  datasets = fastDatasets.snapshot // fastDatasets.noSnapshot;
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
    # Only pools referenced by fileSystems are imported otherwise.
    boot.zfs.extraPools = [ fastPool ];

    # mountpoint=legacy datasets, so the mounts are ordered before the services.
    fileSystems = lib.mapAttrs' (
      name: mountPoint:
      lib.nameValuePair mountPoint {
        device = "${fastPool}/${name}";
        fsType = "zfs";
        options = [ "nofail" ];
      }
    ) datasets;

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

    services.sanoid = {
      enable = true;
      datasets =
        lib.mapAttrs' (
          name: _:
          lib.nameValuePair "${fastPool}/${name}" {
            autoprune = true;
            autosnap = true;
            hourly = 24;
            daily = 14;
            monthly = 3;
            yearly = 0;
          }
        ) fastDatasets.snapshot
        // lib.mapAttrs' (
          name: _:
          lib.nameValuePair "${fastPool}/${name}" {
            autoprune = true;
            autosnap = false;
            hourly = 0;
            daily = 0;
            monthly = 0;
            yearly = 0;
          }
        ) fastDatasets.noSnapshot;
    };
  };
}
