# Migration

Rule: data never exists in only one place. Unraid keeps running until its services and
disks have moved here and been checked.

- [x] NixOS installed on the NVMe, SSH key-only
- [ ] 1. 10 TB as `disk1` (no parity), media stack on it
- [ ] 2. Test end to end
- [ ] 3. Move the unraid disks here
- [ ] 4. Remaining services
- [ ] 5. Retire unraid (keep it as the backup target)
- [ ] 6. Empty the 10 TB onto the array; it becomes parity

Until step 6 the array has no parity: a dead disk loses its files.

## 1. 10 TB as `disk1`, media stack on it

Status: wiped, mounted at `/mnt/disk1` under `/data`, deployed, NVIDIA driver working.
Left: `tailscale up` and the app setup below.

The 10 TB is the first data disk and stays one until step 6. Wipe it before the first
deploy: `/mnt/disk1` is mounted without `nofail`, so an unformatted disk fails the
switch and drops the next boot into emergency mode.

1. Confirm the by-id link points at the 10 TB (an `sdX`, not the NVMe or an SSD), and
   that nothing on it is mounted:
   ```sh
   ls -l /dev/disk/by-id/ | grep ZS5072G6
   lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS /dev/sdX
   ```
2. Stop the old Synology RAID. For every `mdN` in `/proc/mdstat` that lists an `sdX`
   partition (if `lsblk` shows LVM on it, `sudo vgchange -an` first). No
   `/proc/mdstat` at all means nothing was assembled:
   ```sh
   cat /proc/mdstat
   sudo nix run nixpkgs#mdadm -- --stop /dev/mdN
   ```
3. Wipe, partition and format, as one command: an interactive `sudo nix shell` resets
   PATH and loses `parted`.
   ```sh
   sudo nix shell nixpkgs#parted nixpkgs#xfsprogs -c bash -c '
     D=/dev/disk/by-id/ata-ST10000NE0008-2PL103_ZS5072G6
     wipefs -a $D-part* ; wipefs -a $D
     parted -s $D mklabel gpt mkpart disk1 xfs 1MiB 100%
     sleep 2; mkfs.xfs -f -L disk1 $D-part1'
   ```
4. Check: `lsblk -f /dev/sdX` shows one `xfs` partition labelled `disk1`.

Then deploy (README) and reboot once for the NVIDIA driver (`nvidia-smi` should list
the 3060). First-time setup, all on `http://nixos-server:<port>`. The apps reach each
other on `localhost`.

- **Plex:** the first claim must come from localhost:
  `ssh -L 32400:localhost:32400 nixos-server`, then open `http://localhost:32400/web`.
  Libraries: `/data/media/movies`, `/data/media/tv`. Turn on hardware transcoding
  (needs Plex Pass).
- **qBittorrent:** temporary password is in `journalctl -u qbittorrent`. Default save
  path `/data/torrents`, categories `tv` and `movies`. Enable "Keep incomplete torrents
  in" `/scratch/incomplete`.
- **Sonarr / Radarr:** root folders `/data/media/tv` and `/data/media/movies`.
  Download client qBittorrent at `localhost:8080`. Indexers from Jackett.
- **Jackett:** FlareSolverr at `http://localhost:8191`.
- **Bazarr, Seerr, Cleanuparr, Pulsarr, Maintainerr:** point them at Plex and the *arr
  apps on `localhost`.
- **Tdarr:** libraries under `/data/media`, transcode cache `/scratch/transcode`.
- **Tailscale:** `sudo tailscale up --advertise-exit-node` (a bare first `up` drops the
  flag the module set), then approve the exit node in the admin console.

## 2. Test end to end

Request something in Seerr, then check each step:

1. Sonarr/Radarr search it, qBittorrent downloads into `/scratch/incomplete` and moves
   it to `/data/torrents/...` when done.
2. The import is a hardlink: `ls -li` shows the same inode in torrents and media.
3. Plex picks it up, and a forced transcode shows up in `nvidia-smi`.
4. Bazarr fetches subtitles, and Tdarr processes the file on the GPU.
5. Cleanuparr, Pulsarr and Maintainerr can see their connections.

## 3. Move the unraid disks here

They join `disk1` as `disk2`, `disk3`, ... The unraid parity disk stays untouched until
step 6.

1. Check every unraid disk's filesystem (`blkid`). Plain XFS data disks can be
   adopted as they are; btrfs/zfs disks need their data copied instead.
2. Mount each one **read-only** first at `/mnt/diskN` and check the files.
3. Remount read-write and add it to `host.storage.dataDisks`.

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
- Disk health (`smartd`/`scrutiny`), off-box backups.
- **AI:** `host.ai.enable = true`. Before that, add the CUDA binary cache
  (`cuda-maintainers.cachix.org`) or llama.cpp compiles for hours, and move Open WebUI
  off port 8080, which qBittorrent uses.

## 6. Empty the 10 TB onto the array; it becomes parity

1. Stop the media services so nothing writes to `/data`, and check one other data disk
   has room for everything on `disk1` (`df -h /mnt/disk*`).
2. Copy it over in one go, so torrent/library hardlink pairs stay together:
   `sudo rsync -aHX /mnt/disk1/ /mnt/diskN/`, then compare file counts and sizes.
3. Remove `d1` from `host.storage.dataDisks` and the `/mnt/disk1` mount, and deploy.
4. Wipe the 10 TB as in step 1, but label it `parity1` (`mkpart parity1`,
   `mkfs.xfs -L parity1`). Mount it at `/mnt/parity1` and set
   `parityFiles = [ "/mnt/parity1/snapraid.parity" ]`. It must be at least as big as
   the largest data disk.
5. Deploy, then `snapraid sync`, then `snapraid scrub`.
6. Only now reuse or wipe the old unraid parity disk.
