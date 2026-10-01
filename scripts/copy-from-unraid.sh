#!/usr/bin/env bash
# Pulls unraid's `data` share onto the 10 TB disk, so /mnt/user/data/media/movies
# lands at /data/media/movies. Run on nixos-server, inside tmux, after `ssh -A nixos-server`.
# Re-runnable: only changed files are sent and nothing here is deleted.
# Extra arguments go to rsync, e.g. `-n` for a dry run.
set -euo pipefail

dst=/mnt/disk1/

# Unmounted, the copy would silently fill the NVMe root instead.
mountpoint -q "$dst" || {
  echo "$dst is not mounted" >&2
  exit 1
}

rsync=$(nix build --no-link --print-out-paths nixpkgs#rsync)/bin/rsync

# --numeric-ids keeps unraid's 99:100 ownership, which the media services expect.
sudo --preserve-env=SSH_AUTH_SOCK "$rsync" -aHX --numeric-ids --info=progress2 \
  --exclude /media/transcode/ \
  "$@" root@192.168.1.2:/mnt/user/data/ "$dst"
