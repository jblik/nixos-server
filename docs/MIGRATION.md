# Migration

Rule: data never exists in only one place. Unraid keeps running until its services and
disks have moved here and been checked.

- [x] NixOS installed on the NVMe, SSH key-only
- [ ] 1. Media stack on the 10 TB test disk
- [ ] 2. Test end to end
- [ ] 3. Move the unraid disks here; 10 TB becomes parity
- [ ] 4. Remaining services
- [ ] 5. Retire unraid (keep it as the backup target)

## 1. Media stack on the 10 TB test disk

Wipe the 10 TB and make it `disk1`. It still has old Synology RAID partitions, which is
why `md127` may need stopping first.

```sh
ls -l /dev/disk/by-id/ | grep ZS5072G6            # must point at the 10 TB
cat /proc/mdstat                                   # if md127 is listed:
sudo nix run nixpkgs#mdadm -- --stop /dev/md127
sudo nix shell nixpkgs#parted nixpkgs#xfsprogs -c bash -c '
  D=/dev/disk/by-id/ata-ST10000NE0008-2PL103_ZS5072G6
  wipefs -a $D-part* ; wipefs -a $D
  parted -s $D mklabel gpt mkpart disk1 xfs 1MiB 100%
  sleep 2; mkfs.xfs -f -L disk1 $D-part1'
```

Then deploy (README). First-time setup, all on `http://nixos-server:<port>`. The apps
reach each other on `localhost`.

- **Plex:** the first claim must come from localhost:
  `ssh -L 32400:localhost:32400 nixos-server`, then open `http://localhost:32400/web`.
  Libraries: `/data/media/movies`, `/data/media/tv`. Turn on hardware transcoding
  (needs Plex Pass).
- **qBittorrent:** temporary password is in `journalctl -u qbittorrent`. Default save
  path `/data/torrents`, categories `tv` and `movies`.
- **Sonarr / Radarr:** root folders `/data/media/tv` and `/data/media/movies`.
  Download client qBittorrent at `localhost:8080`. Indexers from Jackett.
- **Jackett:** FlareSolverr at `http://localhost:8191`.
- **Bazarr, Seerr, Cleanuparr, Pulsarr, Maintainerr:** point them at Plex and the *arr
  apps on `localhost`.
- **Tdarr:** libraries under `/data/media`, transcode cache `/data/transcode`.

## 2. Test end to end

Request something in Seerr, then check each step:

1. Sonarr/Radarr search it, and qBittorrent downloads into `/data/torrents/...`.
2. The import is a hardlink: `ls -li` shows the same inode in torrents and media.
3. Plex picks it up, and a forced transcode shows up in `nvidia-smi`.
4. Bazarr fetches subtitles, and Tdarr processes the file on the GPU.
5. Cleanuparr, Pulsarr and Maintainerr can see their connections.

## 3. Move the unraid disks here; 10 TB becomes parity

The test data on the 10 TB is thrown away.

1. Check every unraid disk's filesystem (`blkid`). Plain XFS data disks can be
   adopted as they are; btrfs/zfs disks need their data copied instead.
2. Mount each one **read-only** first at `/mnt/diskN` and check the files.
3. Remount read-write and add it to `host.storage.dataDisks`.
4. Reformat the 10 TB as `/mnt/parity1` and set
   `parityFiles = [ "/mnt/parity1/snapraid.parity" ]`. It must be at least as big as
   the largest data disk.
5. `snapraid sync`, then `snapraid scrub`.
6. Only now reuse or wipe the old unraid parity disk.

Paths: unraid's `data` share becomes `/data`, the same path Sonarr and Radarr used
inside their containers. Unraid files are owned 99:100 and gid 100 is `users` here, so
no chown is needed.

## 4. Remaining services

Native where a module exists, container otherwise. Needs secrets first (sops-nix), since
several of these carry API keys and passwords.

- **Before this:** create the ZFS fast pool on the two SATA SSDs for service state.
- paperless (`services.paperless`, replaces the tika and gotenberg containers too),
  immich, forgejo, microbin, speedtest-tracker, pihole (last; set a second DNS server
  on the router first), cloudflared + DDNS, lazylibrarian (container), minecraft
  (`services.minecraft-server` and a backup timer instead of `mc-backup`), your own
  images (laundry-notifier, barracudas4-website).
- Disk health (`smartd`/`scrutiny`), off-box backups, tailscale.
- **AI:** `host.ai.enable = true`. Before that, add the CUDA binary cache
  (`cuda-maintainers.cachix.org`) or llama.cpp compiles for hours, and move Open WebUI
  off port 8080, which qBittorrent uses.
