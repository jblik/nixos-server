# Migration

- [x] NixOS installed on the NVMe, SSH key-only
- [x] 10 TB as `disk1` (no parity), media stack deployed on it with test state
- [x] Unraid's `media/{movies,tv}` copied to `/data/media` (`scripts/copy-from-unraid.sh`)
- [x] 1. Plex
- [x] 2. Sonarr, Radarr, qBittorrent, Jackett, Bazarr
- [ ] 3. Pulsarr, set up fresh (unraid's state is not carried over)
- [ ] 4. Tdarr
- [ ] 5. Maintainerr, Cleanuparr
- [ ] 6. Test end to end
- [ ] 7. Remaining services
- [ ] 8. Retire unraid (keep it as the backup target)
- [ ] 9. Empty the 10 TB onto the array; it becomes parity

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

No app may run older than it did on unraid (a downgrade can't open the newer
database); `packages.nix` keeps them level, see the README's Package versions.

## 4. Tdarr

Unraid's Tdarr state (libraries, flows, plugins, statistics) comes over.

| Unit | Dataset | `pull` |
|---|---|---|
| `tdarr-server`, `tdarr-node-main` | `tdarr` | `pull tdarr/server /var/lib/tdarr/server/server tdarr:users` |

Unraid runs Tdarr 2.91.01, and so does `packages.nix`. Deploy that before the pull;
`systemctl show -p ExecStart tdarr-server` shows `tdarr-server-2.91.01`.

- Only `server/` (the `Tdarr/` folder with `DB2`, `Backups`, `Plugins`) comes over.
  Unraid's `configs/` hold its own IP and node; the NixOS module sets those here. Before
  pulling, `sudo ls /var/lib/tdarr/server` should show the fresh install's `server/Tdarr`
  next to `configs` and `logs`; if `Tdarr` sits elsewhere, pull to that parent instead.
- Stop both units (server and node) before the pull and start the server first.
- Unraid's container saw `/mnt/media/movies`, `/mnt/media/tv` and the cache as `/temp`.
  Per library: source `/data/media/movies` (or `/data/media/tv`), transcode cache
  `/scratch/transcode`. Turn off the library's folder watcher and scan until the paths
  are fixed, so nothing is queued against the old ones. Check flows for hardcoded
  `/mnt/media` or `/temp` paths.
- Nodes: unraid's `ServerNode` shows as offline; the node here is `main`, with one GPU
  transcode and one GPU health-check worker. Run one file: `nvidia-smi` shows it, and
  the result replaces the original in `/data/media`.

## 5. Maintainerr, Cleanuparr

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

Seerr (from `overseerr`) isn't in this order. Move it the same way when you want it, or
drop it.

## 6. Test end to end

Watchlist something in Plex (or request it in Seerr), then check each step:

1. Sonarr/Radarr search it, qBittorrent downloads into `/scratch/incomplete` and moves
   it to `/data/torrents/...` when done.
2. The import is a hardlink: `ls -li` shows the same inode in torrents and media.
3. Plex picks it up, and a forced transcode shows up in `nvidia-smi`.
4. Bazarr fetches subtitles.
5. Cleanuparr and Maintainerr see it.

Also: `systemctl --failed` is empty, and `sudo find /var/lib/<app> ! -user <user>`
prints nothing.

## 7. Remaining services

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

## 8. Retire unraid

1. Router: every port still forwarded to 192.168.1.2 (443, 2222, 25565) goes to .100.
   SMB clients remap to `nixos-server`. Pi-hole's local records go to this box.
2. Leave the stopped containers on unraid for a few weeks as the rollback, then turn it
   into the backup target.

## 9. Empty the 10 TB onto the array; it becomes parity

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
