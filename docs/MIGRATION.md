# Migration

- [x] NixOS installed on the NVMe, SSH key-only
- [ ] 1. 10 TB as `disk1` (no parity), media stack on it
- [ ] 2. Test end to end
- [ ] 3. Remaining services, with empty state
- [ ] 4. Cutover: unraid appdata and disks drop in
- [ ] 5. Retire unraid (keep it as the backup target)
- [ ] 6. Empty the 10 TB onto the array; it becomes parity

Until step 6 the array has no parity: a dead disk loses its files.

Unraid (`jungle-jim`, 192.168.1.2) keeps running everything until step 4. Before that, only
fresh test data exists here, so the unraid apps and disks drop in together at the end.

## 1. 10 TB as `disk1`, media stack on it

- **Plex:** the first claim must come from localhost:
  `ssh -L 32400:localhost:32400 nixos-server`, then open `http://localhost:32400/web`.
  Libraries: `/data/media/movies`, `/data/media/tv`. Turn on hardware transcoding,
  transcoder temporary directory `/scratch/transcode`.
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

## 3. Remaining services, with empty state

Build and test each one here with empty state. Its unraid data comes over in step 4.
A new service gets its dataset before its first deploy:
`sudo zfs create -o mountpoint=legacy fast/<name>`, then add it to `fastDatasets`.

Done: ZFS mirror `fast`; **Forgejo** at `https://git.steenblik.ch`, registration off.
Create the admin with
`sudo -u forgejo forgejo --work-path /var/lib/forgejo admin user create --admin --username <name> --email <email> --random-password`.
SSH clones use `ssh://forgejo@git.steenblik.ch:2222/...`. Forward TCP 2222 on the router.
The router has no NAT loopback, so Pi-hole resolves `git.steenblik.ch` to this box.

Immich and Paperless share one PostgreSQL. Each gets its own role and database over the
unix socket (peer auth, no passwords). Before their first deploy:
`sudo zfs create -o mountpoint=legacy -o recordsize=16k fast/postgresql` and
`sudo zfs create -o mountpoint=legacy fast/paperless`.

- **Immich** at `https://photos.steenblik.ch`, library in `/data/photos`. Create the
  admin right after the first deploy: the first visitor becomes the admin, and the site is
  public. Pi-hole resolves `photos.steenblik.ch` to this box. It is 3.x from unstable:
  26.05 only has the end-of-life 2.x. Machine learning runs in the upstream CUDA image
  on port 3004.
- **Paperless** at `https://paperless.internal.steenblik.ch`, documents in
  `/data/documents`, Tika and Gotenberg on. Admin: `sudo paperless-manage createsuperuser`.

In order:

| Service | On unraid | Here | Brought over in step 4 |
|---|---|---|---|
| Secrets | — | sops-nix, including the Cloudflare tokens in `/var/lib/secrets` | — |
| Samba | `data` and `appdata` SMB shares | `services.samba`, sharing `/data` | nothing (the files come with the disks) |
| Paperless | `bear-docs` + `Redis`, `apache-tika-server`, `gotenberg` | `services.paperless`, `configureTika`, `mediaDir = /data/documents`, PostgreSQL | `document_exporter` on unraid, `paperless-manage document_importer` here; both on the same Paperless version (2.20.15) |
| Immich | not running (`photos` is empty) | `services.immich` | nothing, new install |
| Microbin | `microbin` | `services.microbin` | `microbin` |
| Speedtest Tracker | `speedtest-tracker` | `services.speedtest-tracker` | `speedtest-tracker` |
| Disk health, backups | unraid notifications | `smartd`/scrutiny, off-box backups (unraid becomes the target) | — |
| AI | — | `host.ai.enable = true` after adding `cuda-maintainers.cachix.org` and moving Open WebUI off 8080 | — |

Not carried over (appdata only, no container): `tautulli`, `immich`, `forgejo`,
`convertx`, `unpackerr`, `prefetcharr`, `Alexa-Subwatch`, `tdarr-backup`.
`cloudflareddns` is replaced by `cloudflare-dyndns`.

## 4. Cutover: unraid appdata and disks drop in

Do this in one session. If the *arr apps start with their old databases but without
the unraid disks, they see the library as missing and start grabbing it again.

1. **Stop unraid's apps.** In the Docker tab, stop every container except Pi-hole
   (unless it already moved here) and turn off autostart. The containers stay as the rollback.
2. **Stage appdata here.** Run on nixos-server, via `ssh -A nixos-server`, in `nix shell nixpkgs#rsync`:
   ```sh
   mkdir -p ~/import
   rsync -aH --info=progress2 --exclude 'log/' --exclude 'logs/' --exclude 'Logs/' --exclude 'Cache/' --exclude 'Codecs/' --exclude 'transcode/' \
     root@192.168.1.2:/mnt/user/appdata/{sonarr,radarr,bazarr,jackett,qbittorrent,overseerr,plex,Cleanuparr,pulsarr,maintainerr,paperless-ngx,microbin,speedtest-tracker,lazylibrarian,minecraft} ~/import/
   ```
   `~/import` stays as an untouched backup. Export Tdarr's flows from its UI now; Tdarr
   itself starts fresh.
3. **Move the disks.** Shut unraid down. The disks join as `disk2`, `disk3`, ...; the
   unraid parity disk stays untouched until step 6.
   1. Check each disk's filesystem (`blkid`). XFS disks are adopted as they are;
      btrfs/zfs disks need their data copied instead.
   2. Mount it **read-only** at `/mnt/diskN` and check the files.
   3. Remount read-write and add it to `host.storage.dataDisks`.

   Unraid's `data` share maps to `/data`; its 99:100 ownership already matches, no chown.
4. **Put the appdata in place.**
   ```sh
   sudo zfs snapshot -r fast@pre-import
   sudo systemctl stop sonarr radarr bazarr jackett qbittorrent seerr plex podman-cleanuparr podman-pulsarr podman-maintainerr   # + step 3 services
   put() { sudo rsync -a --delete --chown="$3" "$1"/ "$2"/; }
   put ~/import/sonarr /var/lib/sonarr/.config/NzbDrone sonarr:users   # and so on, per the table
   ```
   The native services run as their own users, not unraid's 99, so every copy needs
   `--chown`.

   | App | From `~/import/` | To | Owner |
   |---|---|---|---|
   | Sonarr | `sonarr` | `/var/lib/sonarr/.config/NzbDrone` | `sonarr:users` |
   | Radarr | `radarr` | `/var/lib/radarr/.config/Radarr` | `radarr:users` |
   | Bazarr | `bazarr` | `/var/lib/bazarr` | `bazarr:users` |
   | Jackett | `jackett` (all of it: `DataProtection` holds the indexer password keys) | `/var/lib/jackett/.config/Jackett` | `jackett:jackett` |
   | qBittorrent | `qbittorrent/config`, `qbittorrent/data` | `/var/lib/qBittorrent/qBittorrent/{config,data}` | `qbittorrent:users` |
   | Seerr | `overseerr` | `/var/lib/private/seerr` | `root:root` (DynamicUser, systemd re-chowns it) |
   | Plex | the folder with `Preferences.xml` | `/var/lib/plex/Plex Media Server` | `plex:users` |
   | Cleanuparr, Pulsarr, Maintainerr | `Cleanuparr`, `pulsarr`, `maintainerr` | `/var/lib/<name>` | `99:100` |
   | Step 3 services | as in the step 3 table | their `dataDir` | their service user |

5. **Fix the container paths.** Start the services, then:

   | App | Unraid container saw | Fix |
   |---|---|---|
   | Sonarr / Radarr | `/data` = the share | root folders already match. Set qBittorrent and Jackett to `localhost`, delete remote path mappings |
   | qBittorrent | `/data` = `data/torrents` | Pause all. Per category, "Set location" to `/data/torrents/<cat>`; the recheck finishes without downloading. Redo the step 1 settings (paths, WebUI domain) |
   | Bazarr | `/data` = `data/media` | delete the path mappings |
   | Plex | `/data` = `data/media` | Per library, add `/data/media/<lib>`, scan, then remove the old folder (keeps watch state). Transcoder temp dir `/scratch/transcode` |
   | Seerr, Pulsarr, Maintainerr | — | Plex and *arr hosts to `localhost` |
   | Cleanuparr | `/downloads` = `data/torrents` | becomes `/data/torrents` |
   | LazyLibrarian | `/downloads`, `/books`, `/importbooks` | `/data/torrents/books`, `/data/media/books`, `/data/media/importbooks` |
   | Tdarr | `/mnt/media/...` | fresh install. Import the flows, libraries under `/data/media` |

6. **Point the outside world here.** On the router, forward 32400, 443, 2222 and 25565
   to 192.168.1.100. SMB clients remap to `nixos-server`. Pi-hole's local records go to
   this box.
7. **Check:**
   - `systemctl --failed` is empty. The journal of each service shows no
     permission or database errors.
   - `sudo find /var/lib/<app> ! -user <user>` prints nothing.
   - In the *arr apps, System → Health is clean, and the download client and indexers
     pass Test. Jackett: "Test all".
   - qBittorrent shows the same torrent count as unraid, all seeding after the recheck.
   - Plex shows its watch history and users, and plays remotely.
   - Seerr shows the old requests, and its Plex and *arr tests pass.
   - Paperless shows the documents.
   - Then run step 2 again.

   Rollback for one app: `sudo systemctl stop <app> && sudo zfs rollback fast/<app>@pre-import`.

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
