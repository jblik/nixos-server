# Storage — replacing the unraid array

The unraid array is the one thing this repo had no answer for. This is the design.

## 1. What unraid was actually giving you

Worth naming, because it is easy to pick a "better" filesystem that quietly drops
half of these:

| Property | Why it matters |
|---|---|
| **Mixed disk sizes** | You add whatever drive is cheap this year, not a matched set. |
| **Add a disk any time** | No rebuild, no rebalance, no vdev planning. |
| **Per-disk filesystems** | Lose more disks than you have parity for and you lose *those disks' files* — not the entire pool. This is unraid's real safety property and most RAID does not have it. |
| **Independent spin-down** | Reading one file spins one disk. Power and noise, on a box that idles 23 h/day. |
| **Real-time single-disk parity** | A drive dies, you rebuild from parity. |
| **A dashboard for disk health** | SMART, temperatures, array status. |

Anything that keeps 1–5 is a real replacement. ZFS keeps only 6-ish of them, which is
why the recommendation below is not "just use ZFS for everything".

## 2. The design: two tiers

Unraid itself is two tiers (cache pool + parity array). Keep that shape — it maps to
the workloads correctly.

```
  ┌──────────────── FAST TIER — ZFS mirror, 2× SSD/NVMe ────────────────┐
  │  /var/lib/<service>      service state, *arr databases              │
  │  PostgreSQL (immich, paperless)   Redis                             │
  │  /var/lib/libvirt/images  VM disks                                  │
  │  /var/lib/models          GGUF weights (read constantly, want SSD)  │
  │  /var/cache/transcode     Plex/Tdarr scratch (keep off the HDDs)    │
  │  → snapshots (sanoid), replicated off-box (syncoid / restic)        │
  └──────────────────────────────────────────────────────────────────────┘

  ┌──────────── BULK TIER — mergerfs union + SnapRAID parity ───────────┐
  │  /mnt/disk1  /mnt/disk2  /mnt/disk3 ...   each its own XFS          │
  │        └──────────── mergerfs ───────────┘                          │
  │                    /mnt/storage                                     │
  │   media/  photos/  documents/  downloads/  backups/                 │
  │                                                                     │
  │  /mnt/parity1 (+ /mnt/parity2)  ← SnapRAID parity, nightly sync     │
  └──────────────────────────────────────────────────────────────────────┘
```

**Fast tier — ZFS mirror.** Two SSDs, `zpool create fast mirror ...`. Everything that
is small, hot, and changes constantly. ZFS earns its place here: checksums, atomic
snapshots before every `nixos-rebuild`, and `zfs send` replication that is far better
than rsyncing a live database.

**Bulk tier — mergerfs + SnapRAID.** Each HDD gets its own XFS filesystem mounted at
`/mnt/diskN`. mergerfs unions them into a single `/mnt/storage` that services see as
one big directory tree. SnapRAID computes parity across the disks on a schedule.

This is the combination that preserves properties 1–5 above. It is the standard
unraid-alternative stack and both halves have first-class NixOS support:
`services.snapraid` (with `dataDisks`, `parityFiles`, `contentFiles`, `sync.interval`,
`scrub.interval`) and the `mergerfs` package driven from `fileSystems`.

## 3. The honest downsides of SnapRAID

Say these out loud before committing:

- **Parity is point-in-time, not real-time.** A file written after the last nightly
  sync is unprotected until the next one. For media and archives — write once, read
  forever — this is fine. For a database it is useless, which is exactly why databases
  live on the ZFS tier.
- **`snapraid sync` propagates deletions.** Delete a file, sync, and parity forgets it
  too. **SnapRAID is not a backup.** It survives a *disk* dying, not you.
- **Restores are slow.** Rebuilding a 12 TB disk from parity reads every other disk in
  full. Expect the better part of a day.
- **No striping means no striped read speed.** A single file reads at one disk's speed
  (~150–250 MB/s). For streaming media that is irrelevant; for a Tdarr pass over a
  4K remux it is noticeable.
- **You must run `snapraid scrub` regularly** or silent corruption goes undetected
  until you need parity, which is the worst possible moment. The NixOS module
  schedules this — use it.

## 4. Why not the alternatives

| Option | Why not |
|---|---|
| **All-ZFS (one raidz2)** | Best integrity by a distance, and if you had a matched set of disks and enough RAM it would be the right answer. But: all disks spin for every read, mixed sizes are truncated to the smallest, and although RAIDZ expansion exists now (OpenZFS 2.3) it expands *a vdev* and does not rebalance existing data. Lose more disks than parity and the whole pool is gone, not one disk's files. It trades away four of the six properties in §1. |
| **btrfs raid5/6** | Still carries the write-hole warning. Not for the only copy of your data. |
| **btrfs raid1** | Fine and flexible with mixed sizes, but costs 50% of capacity — expensive for a media library. |
| **mdadm + LVM** | Real-time parity, but requires same-size disks, spins everything, and has no checksums, so bitrot is invisible. |
| **bcachefs** | Genuinely interesting for exactly this use case. Too young to hold the only copy of a decade of data. |

**If you disagree and want all-ZFS anyway**, the design still works: keep the fast
mirror, replace the bulk tier with a raidz2 vdev, and drop the mergerfs/snapraid
module. The service configs do not care — they only see `/mnt/storage`.

## 5. The migration shortcut this unlocks

Unraid data disks are **plain single-disk XFS filesystems with no striping**. The array
is a union + parity, exactly like mergerfs + SnapRAID. That means:

> Unraid data disks can be pulled, plugged into the NixOS box, mounted read-only,
> verified, and then adopted into mergerfs + SnapRAID **without copying a single byte**.

Only parity has to be rebuilt from scratch. This turns what would be a
copy-tens-of-terabytes-over-gigabit project (days, and a second full set of disks) into
an afternoon. It is the strongest practical argument for choosing SnapRAID here.

Rules for doing it safely — see [MIGRATION.md](MIGRATION.md) phase 3:

1. Confirm every data disk is XFS first (`blkid`). Unraid can also use btrfs or zfs
   per disk; those need different handling.
2. Mount **read-only** on first contact and verify contents before writing anything.
3. **Do not touch the unraid parity disk until the new SnapRAID parity has fully
   synced and scrubbed.** That old parity is your rollback.
4. Move disks in batches, keeping the unraid array bootable and valid until the last
   batch. Never let a batch exist only on the new machine unverified.

## 6. Configuration sketch

The knobs land in `modules/options.nix` as `host.storage.*` and are set per-host, in the
same style as `host.gpu.*`:

```nix
host.storage = {
  fastPool  = "fast";                                    # ZFS pool name
  bulkMount = "/mnt/storage";                            # mergerfs union
  dataDisks = {                                          # label -> mountpoint
    d1 = "/mnt/disk1";
    d2 = "/mnt/disk2";
    d3 = "/mnt/disk3";
  };
  parityFiles = [ "/mnt/parity1/snapraid.parity" ];
};
```

mergerfs mount options that matter, and why:

| Option | Reason |
|---|---|
| `category.create=mfs` | New files go to the disk with most free space. Use `epmfs` instead if you want a whole show/season to stay on one disk (fewer disks spun up per playback). |
| `minfreespace=50G` | Stop filling a disk before it is dangerously full. |
| `moveonenospc=true` | Transparently relocate a write that hits a full disk. |
| `dropcacheonclose=true` | Prevents double-caching with `cache.files=partial`. |
| `use_ino` | Consistent inode numbers across the union — hardlinks behave, which the *arr stack and qBittorrent care about a lot. |
| `allow_other` | Services run as their own users, not root. |
| `noatime` (per-disk XFS) | Do not spin a disk up just to record a read. |

**Hardlinks matter.** qBittorrent + *arr atomic-moves only work when downloads and the
media library are on the *same filesystem*. Under mergerfs they must also land on the
same underlying disk. Keep `downloads/` and `media/` under one mergerfs mount and use a
create policy that keeps a torrent and its hardlinked copy together, or you will
silently start copying every file instead of linking it — and double your disk usage.

## 7. Things unraid gave you that you must now configure explicitly

- **Disk health / SMART dashboard** — `services.smartd` for alerts, plus
  `services.scrutiny` for the web UI. Unraid had this built in; NixOS does not.
- **Spin-down** — `hdparm`/`hd-idle` per disk. Not automatic.
- **Share-level SMB/NFS exports** — `services.samba` / `services.nfs.server`, declared
  explicitly rather than clicked in a UI.
- **The array status page** — replaced by SnapRAID's sync/scrub logs plus whatever
  monitoring you add. Wire failures to a notification you will actually see.

## 8. Backup — the part consolidation makes urgent

Two machines gave you an accidental second copy. One machine does not. Parity is not a
backup (§3). Concretely:

- **Keep the unraid box.** Wipe it, install anything (unraid, TrueNAS, plain Debian),
  and use it purely as a restic/borg target on the LAN. It is the cheapest possible
  3-2-1 second copy and the hardware already exists.
- **Offsite for the irreplaceable subset** — photos, documents, service state. Not the
  media library. `services.restic` to Backblaze B2 or similar.
- **ZFS snapshots on the fast tier** (`services.sanoid`) so a bad `nixos-rebuild` or a
  botched Immich upgrade is a rollback, not an incident.
