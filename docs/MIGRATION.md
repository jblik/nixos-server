# Migration

- [x] NixOS installed on the NVMe, SSH key-only
- [x] 10 TB as `disk1` (no parity), media stack deployed on it with test state
- [x] Unraid's `media/{movies,tv}` copied to `/data/media` (`scripts/copy-from-unraid.sh`)
- [ ] 1. Plex
- [ ] 2. Sonarr, Radarr, qBittorrent, Jackett, Bazarr
- [ ] 3. Pulsarr
- [ ] 4. Maintainerr, Cleanuparr
- [ ] 5. Test end to end
- [ ] 6. Remaining services
- [ ] 7. Retire unraid (keep it as the backup target)
- [ ] 8. Empty the 10 TB onto the array; it becomes parity

Unraid (`jungle-jim`, 192.168.1.2) is the source and the rollback: nothing there is
changed or deleted. Each app moves the same way: stop it on unraid, pull its appdata
straight into place here, fix the paths that differ, check it.

## Moving an app

Run on nixos-server, via `ssh -A nixos-server`, inside tmux. Once per shell:

```sh
rsync=$(nix build --no-link --print-out-paths nixpkgs#rsync)/bin/rsync
# pull <unraid appdata dir> <dest> <owner>
pull() {
  sudo --preserve-env=SSH_AUTH_SOCK "$rsync" -aH --delete --info=progress2 --chown="$3" \
    --exclude log/ --exclude logs/ --exclude Logs/ --exclude Cache/ --exclude Codecs/ \
    --exclude transcode/ --exclude '*.pid' \
    "root@192.168.1.2:/mnt/user/appdata/$1/" "$2/"
}
```

For each app:

1. Stop it on unraid (Docker tab), and turn off its autostart.
2. Here: `sudo systemctl stop <unit>`, then `sudo zfs snapshot fast/<dataset>@pre-import`.
3. `pull ...` with the row from the step's table.
4. `sudo systemctl start <unit>`, and watch `journalctl -fu <unit>` for database or
   permission errors.
5. Fix the paths in its UI, as listed in the step.

Rollback for one app: `sudo systemctl stop <unit> && sudo zfs rollback fast/<dataset>@pre-import`,
and start it on unraid again.

Plex, Radarr and Bazarr run from nixpkgs-unstable so they are not older than unraid's
(a downgrade can't open the newer database). Sonarr is 4.0.19 here and 4.0.20 on unraid,
which nixpkgs doesn't have yet: if its journal shows a migration error, roll it back
and say so.

## 1. Plex

Unraid's Plex keeps running until now; two Plex servers with the same identity must
never run at once.

| Unit | Dataset | `pull` |
|---|---|---|
| `plex` | `plex` | `pull plex "/var/lib/plex/Plex Media Server" plex:users` |

1. Deploy (Plex is now 1.43.4, from unstable).
2. Stop Plex on unraid, turn off autostart. Stop, snapshot, pull, start here (4 GB).
3. Open `https://plex.internal.steenblik.ch` (or `http://192.168.1.100:32400/web`).
   Signed in, the server shows up under its old name.
4. Settings → Library: turn **off** "Empty trash automatically after every scan" before
   anything scans. Unraid's container saw `/data` = `data/media`, so every library
   points at `/data/movies` or `/data/tv`, which don't exist here.
5. Per library: Edit → Add folders → `/data/media/movies` (or `/data/media/tv`), save,
   scan. When the items show as available again, remove the old `/data/...` folder.
   This keeps watch state, posters and collections.
6. Libraries for folders that were not copied (books, music) can be deleted.
7. Settings → Transcoder: temporary directory `/scratch/transcode`, hardware
   acceleration on. Play something with a forced low quality: `nvidia-smi` shows the
   transcode.
8. Router: forward 32400 to 192.168.1.100 instead of .2. Settings → Remote Access is
   green.
9. Turn "Empty trash automatically" back on if it was on.

## 2. Sonarr, Radarr, qBittorrent, Jackett, Bazarr

Do these together: they point at each other. Jackett is still running on unraid; stop
it too.

First copy the downloads that are still seeding (16 GB, not in the media copy), so
qBittorrent finds its torrents complete:

```sh
sudo --preserve-env=SSH_AUTH_SOCK "$rsync" -aHX --numeric-ids --info=progress2 \
  root@192.168.1.2:/mnt/user/data/torrents/{tv,movies} /mnt/disk1/torrents/
```

Then stop, snapshot, pull and start each of them:

| Unit | Dataset | `pull` |
|---|---|---|
| `sonarr` | `sonarr` | `pull sonarr /var/lib/sonarr/.config/NzbDrone sonarr:users` |
| `radarr` | `radarr` | `pull radarr /var/lib/radarr/.config/Radarr radarr:users` |
| `jackett` | `jackett` | `pull jackett /var/lib/jackett/.config/Jackett jackett:jackett` |
| `qbittorrent` | `qbittorrent` | `pull qbittorrent/config /var/lib/qBittorrent/qBittorrent/config qbittorrent:users`, the same for `data` |
| `bazarr` | `bazarr` | `pull bazarr /var/lib/bazarr bazarr:users` |

Unraid ran them on a docker network, so they reach each other by container name
(`http://jackett:9117` and so on). Here everything is `localhost`.

- **Jackett:** FlareSolverr at `http://localhost:8191`. "Test all".
- **qBittorrent:** unraid's container saw `/data` = `data/torrents`. Pause all. Options →
  Downloads: default save path `/data/torrents`, "Keep incomplete torrents in"
  `/scratch/incomplete`. Per category, save path `/data/torrents/<cat>`. Select each
  category's torrents → "Set location" `/data/torrents/<cat>`; the recheck finds them
  complete. Resume. Options → WebUI: add `qbittorrent.internal.steenblik.ch` to the
  server domains (or turn off host header validation), or logins through the proxy fail.
- **Sonarr / Radarr:** unraid saw the whole share as `/data`, so root folders
  (`/data/media/tv`, `/data/media/movies`) already match. Settings → Download Clients:
  qBittorrent host `localhost`, port 8080. Delete every Remote Path Mapping. Indexers:
  each Jackett URL to `http://localhost:9117/...`. Connect: Plex host `localhost`.
  System → Status shows the Radarr version, System → Health is clean, Test passes
  everywhere.
- **Bazarr:** unraid saw `/data` = `data/media`. Settings → Sonarr/Radarr: host
  `localhost`, and delete the path mappings. Run a subtitle search on one episode.

## 3. Pulsarr

| Unit | Dataset | `pull` |
|---|---|---|
| `podman-pulsarr` | `pulsarr` | `pull pulsarr /var/lib/pulsarr 99:100` |

- Plex, Sonarr and Radarr instances: host `localhost`. Saving them re-creates Pulsarr's
  webhooks in Sonarr/Radarr; check Settings → Connect there points at
  `http://localhost:3003`.
- Add something to a Plex watchlist: it shows up in Sonarr or Radarr.

## 4. Maintainerr, Cleanuparr

| Unit | Dataset | `pull` |
|---|---|---|
| `podman-maintainerr` | `maintainerr` | `pull maintainerr /var/lib/maintainerr 99:100` |
| `podman-cleanuparr` | `cleanuparr` | `pull Cleanuparr /var/lib/cleanuparr 99:100` |

- **Maintainerr:** Plex, Sonarr, Radarr hosts to `localhost`. Tautulli and Overseerr
  aren't coming; drop them, and fix rules that used them. Check a rule's media list
  before enabling deletes.
- **Cleanuparr:** unraid's container saw `/downloads` = `data/torrents`. Every
  `/downloads/...` path becomes `/data/torrents/...`. qBittorrent, Sonarr, Radarr hosts
  to `localhost`. Run it in dry-run once if the option is there.

Seerr (from `overseerr`) and Tdarr (fresh; export its flows on unraid first) aren't in
this order. Move them the same way when you want them, or drop them.

## 5. Test end to end

Watchlist something in Plex (or request it in Seerr), then check each step:

1. Sonarr/Radarr search it, qBittorrent downloads into `/scratch/incomplete` and moves
   it to `/data/torrents/...` when done.
2. The import is a hardlink: `ls -li` shows the same inode in torrents and media.
3. Plex picks it up, and a forced transcode shows up in `nvidia-smi`.
4. Bazarr fetches subtitles.
5. Cleanuparr and Maintainerr see it.

Also: `systemctl --failed` is empty, and `sudo find /var/lib/<app> ! -user <user>`
prints nothing.

## 6. Remaining services

A new service gets its dataset before its first deploy:
`sudo zfs create -o mountpoint=legacy fast/<name>`, then add it to `fastDatasets`. Its
unraid appdata comes over with `pull`, like the media apps.

The router has no NAT loopback, so Pi-hole resolves `git.steenblik.ch` to this box.

| Service | On unraid | Here |
|---|---|---|
| Samba | `data` and `appdata` SMB shares | `services.samba`, sharing `/data` |
| Speedtest Tracker | `speedtest-tracker` | `services.speedtest-tracker` |
| Disk health, backups | unraid notifications | `smartd`/scrutiny, off-box backups (unraid becomes the target) |
| AI | — | `host.ai.enable = true` after adding `cuda-maintainers.cachix.org` and moving Open WebUI off 8080 |

Not carried over (appdata only, no container): `tautulli`, `immich`, `forgejo`,
`convertx`, `unpackerr`, `prefetcharr`, `Alexa-Subwatch`, `tdarr-backup`.
`cloudflareddns` is replaced by `cloudflare-dyndns`.

## 7. Retire unraid

1. Router: every port still forwarded to 192.168.1.2 (443, 2222, 25565) goes to .100.
   SMB clients remap to `nixos-server`. Pi-hole's local records go to this box.
2. Leave the stopped containers on unraid for a few weeks as the rollback, then turn it
   into the backup target.

## 8. Empty the 10 TB onto the array; it becomes parity

Needs a data disk at least as big as what's on `disk1`.

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
