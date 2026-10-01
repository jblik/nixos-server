{ config, lib, ... }:
# Bulk tier, part 2: parity.
#
# SnapRAID computes parity across the data disks on a schedule, so a failed disk
# can be rebuilt. Two things to keep in mind:
#
#   * Parity is point-in-time. Anything written since the last sync is unprotected
#     until the next one. Fine for media; useless for databases — which is exactly
#     why databases live on the ZFS tier instead.
#   * `snapraid sync` propagates deletions. This is NOT a backup. It survives a
#     disk dying, not a mistake.
let
  cfg = config.host.storage;
  hasDisks = cfg.dataDisks != { };
  enabled = hasDisks && cfg.parityFiles != [ ];

  # SnapRAID wants at least (parity + 1) content files, on different disks.
  # One per data disk satisfies that for any sane parity count.
  derivedContent = map (mnt: "${mnt}/snapraid.content") (lib.attrValues cfg.dataDisks);
in
{
  config = {
    warnings = lib.optional (hasDisks && !enabled) ''
      host.storage.dataDisks is set but host.storage.parityFiles is empty: the
      bulk array has NO parity and a single disk failure loses that disk's data.
    '';

    services.snapraid = lib.mkIf enabled {
      enable = true;
      dataDisks = cfg.dataDisks;
      parityFiles = cfg.parityFiles;
      contentFiles = if cfg.contentFiles == [ ] then derivedContent else cfg.contentFiles;
      exclude = cfg.exclude;

      sync.interval = cfg.syncInterval;
      scrub = {
        interval = cfg.scrubInterval;
        # Verify 12% of the array per run, never re-checking data scrubbed in the
        # last 10 days: the whole array gets covered roughly monthly. Scrubbing is
        # what turns silent corruption into a warning instead of a failed restore.
        plan = 12;
        olderThan = 10;
      };

      extraConfig = ''
        # Skip hidden files (e.g. in-progress downloads that rename on completion).
        nohidden
        # Checkpoint long syncs so an interrupted run does not start over.
        autosave 500
      '';
    };
  };
}
