# Migration

- [x] NixOS installed on the NVMe, SSH key-only
- [ ] 1. 10 TB as `disk1` (no parity), media stack on it
- [ ] 2. Test end to end
- [ ] 3. Move the unraid disks here
- [ ] 4. Remaining services
- [ ] 5. Retire unraid (keep it as the backup target)
- [ ] 6. Empty the 10 TB onto the array; it becomes parity

Until step 6 the array has no parity: a dead disk loses its files.

## 1. 10 TB as `disk1`, media stack on it

Done: disk formatted and mounted under `/data`, all services running, GPU working,
Tailscale up as an exit node, nginx in front of every UI. Left: first-time app setup,
all on `https://<app>.internal.steenblik.ch`. The apps reach each other on `localhost`.

- **Plex:** the first claim must come from localhost:
  `ssh -L 32400:localhost:32400 nixos-server`, then open `http://localhost:32400/web`.
  Libraries: `/data/media/movies`, `/data/media/tv`. Turn on hardware transcoding
  (needs Plex Pass).
- **qBittorrent:** temporary password is in `journalctl -u qbittorrent`. Default save
  path `/data/torrents`, categories `tv` and `movies`. Enable "Keep incomplete torrents
  in" `/scratch/incomplete`. Add `qbittorrent.internal.steenblik.ch` to the WebUI server
  domains (or turn off host header validation), or logins through the proxy fail.
- **Sonarr / Radarr:** root folders `/data/media/tv` and `/data/media/movies`.
  Download client qBittorrent at `localhost:8080`. Indexers from Jackett.
- **Jackett:** FlareSolverr at `http://localhost:8191`.
- **Bazarr, Seerr, Cleanuparr, Pulsarr, Maintainerr:** point them at Plex and the *arr
  apps on `localhost`.
- **Seerr:** Application URL `https://seerr.steenblik.ch`, and turn on "Enable Proxy
  Support".
- **Tdarr:** libraries under `/data/media`, transcode cache `/scratch/transcode`.

## 2. Test end to end

Request something in Seerr, then check each step:

1. Sonarr/Radarr search it, qBittorrent downloads into `/scratch/incomplete` and moves
   it to `/data/torrents/...` when done.
2. The import is a hardlink: `ls -li` shows the same inode in torrents and media.
3. Plex picks it up, and a forced transcode shows up in `nvidia-smi`.
4. Bazarr fetches subtitles, and Tdarr processes the file on the GPU.
5. Cleanuparr, Pulsarr and Maintainerr can see their connections.

## 3. Move the unraid disks here

They join as `disk2`, `disk3`, ... The unraid parity disk stays untouched until step 6.

1. Check each disk's filesystem (`blkid`). XFS disks are adopted as they are; btrfs/zfs
   disks need their data copied instead.
2. Mount it **read-only** at `/mnt/diskN` and check the files.
3. Remount read-write and add it to `host.storage.dataDisks`.

Unraid's `data` share maps to `/data`; its 99:100 ownership already matches, no chown.

## 4. Remaining services

- Secrets (sops-nix) first; several of these carry API keys and passwords. Move the
  Cloudflare tokens in `/var/lib/secrets` there too.
- **ZFS fast pool** on the two SATA SSDs, for service state. The first deploy with
  `fastPool` set loads ZFS; `zfs-import-fast` fails until the pool exists. Then (wipes both SSDs):
  ```sh
  S=/dev/disk/by-id/ata-SanDisk_SSD_PLUS_240GB_1838D3805791
  P=/dev/disk/by-id/ata-PEAQ_SSD_256GB_67007Y8J3000079
  sudo wipefs -a $S-part1 $P-part1 $S $P
  sudo zpool create -o ashift=12 -O compression=zstd -O atime=off \
    -O xattr=sa -O acltype=posixacl -O mountpoint=none fast mirror $S $P
  ```
  Move each entry of `host.storage.fastDatasets` onto its dataset before deploying it
  (stop the services first; the `.old` copies are the rollback):
  ```sh
  mv_ds() { sudo zfs create -o mountpoint=legacy fast/$1 && sudo mount -t zfs fast/$1 /mnt/tmp &&
    sudo rsync -aHAX --numeric-ids "$2/" /mnt/tmp/ && sudo umount /mnt/tmp && sudo mv "$2" "$2.old"; }
  sudo mkdir -p /mnt/tmp
  mv_ds forgejo /var/lib/forgejo   # ...and so on per entry
  ```
  Deploy, start the services, check `findmnt -t zfs`, then delete the `.old` copies.
  Point Plex's transcoder temporary directory at `/scratch/transcode`, off the pool.
- **Forgejo:** running at `https://git.steenblik.ch`, registration off. Create the admin:
  `sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user create --admin --username <name> --email <email> --random-password`
  SSH clones use `ssh://forgejo@git.steenblik.ch:2222/...`; forward TCP 2222 on the router.
  The router has no NAT loopback, so the unraid Pi-hole resolves `git.steenblik.ch` to
  this box; recreate that record when pihole moves here.
- paperless (also replaces tika and gotenberg), immich, microbin,
  speedtest-tracker, pihole (last; set a second DNS server on the router first),
  lazylibrarian, minecraft (with a backup timer), laundry-notifier,
  barracudas4-website.
- Disk health (`smartd`/`scrutiny`), off-box backups.
- **AI:** `host.ai.enable = true`, after adding the CUDA binary cache
  (`cuda-maintainers.cachix.org`) and moving Open WebUI off port 8080 (qBittorrent).

## 6. Empty the 10 TB onto the array; it becomes parity

1. Stop the media services and check one data disk has room for all of `disk1`
   (`df -h /mnt/disk*`).
2. Copy in one go so hardlink pairs stay together:
   `sudo rsync -aHX /mnt/disk1/ /mnt/diskN/`, then compare file counts and sizes.
3. Remove `d1` from `host.storage.dataDisks` and the `/mnt/disk1` mount, and deploy.
4. Wipe and format it as `parity1`:
   ```sh
   sudo nix shell nixpkgs#parted nixpkgs#xfsprogs -c bash -c '
     D=/dev/disk/by-id/ata-ST10000NE0008-2PL103_ZS5072G6
     wipefs -a $D-part* ; wipefs -a $D
     parted -s $D mklabel gpt mkpart parity1 xfs 1MiB 100%
     sleep 2; mkfs.xfs -f -L parity1 $D-part1'
   ```
5. Mount it at `/mnt/parity1`, set `parityFiles = [ "/mnt/parity1/snapraid.parity" ]`
   (it must be at least as big as the largest data disk), deploy, then `snapraid sync`
   and `snapraid scrub`.
6. Only now reuse or wipe the old unraid parity disk.
