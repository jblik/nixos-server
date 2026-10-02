# Migration

- [x] NixOS installed on the NVMe, SSH key-only
- [x] 10 TB as `disk1` (no parity), media stack deployed on it with test state
- [x] Unraid's `media/{movies,tv}` copied to `/data/media` (`scripts/copy-from-unraid.sh`)
- [x] 1. Plex
- [x] 2. Sonarr, Radarr, qBittorrent, Jackett, Bazarr
- [x] 3. Pulsarr, set up fresh (unraid's state is not carried over)
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

## 8. Retire unraid

1. Router: every port still forwarded to 192.168.1.2 (443, 2222, 25565) goes to .100.
   SMB clients remap to `nixos-server`. Pi-hole's local records go to this box.
2. Leave the stopped containers on unraid for a few weeks as the rollback, then turn it
   into the backup target.
