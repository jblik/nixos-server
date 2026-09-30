# nixos-server

One NixOS box (Ryzen 2700X, RTX 3060, 32 GB) replacing the unraid server.
Progress and next steps: [docs/MIGRATION.md](docs/MIGRATION.md).

## Layout

```
flake.nix                    nixosConfigurations.nixos-server
hosts/nixos-server/          hardware config + site knobs (disks, subnet, what's enabled)
modules/options.nix          the `host.*` knobs
modules/system/              boot, network/firewall, nix, users, ssh
modules/hardware/            nvidia driver
modules/storage/             mergerfs union, snapraid parity, zfs fast pool, spin-down
modules/services/            media stack, *arr, AI (off)
```

Firewall: SSH and Plex are open; every other UI is LAN-only (`host.lanCidr`).

## Deploy

Edit on the Mac, then:

```sh
rsync -a --delete --exclude .git --exclude .jj --exclude .idea --exclude .claude \
  --exclude unraid-export ./ nixos-server:nixos-server/
ssh -t nixos-server 'sudo nixos-rebuild switch --flake ~/nixos-server#nixos-server'
```

A bad generation can be rolled back with `sudo nixos-rebuild switch --rollback`, or by
picking an older entry in the boot menu.

## Storage

- **Bulk:** one XFS filesystem per HDD at `/mnt/diskN`, merged by mergerfs into
  `/data`, parity by SnapRAID (enabled once `parityFiles` is set). Like unraid: mixed
  sizes, disks spin down on their own, and losing a disk only loses that disk's files.
- **Fast (planned):** ZFS mirror on the two SATA SSDs for service state.

`/data` layout: `torrents/{tv,movies}`, `media/{tv,movies}`. Downloads and the library
share one mount so imports are hardlinks. In-progress downloads and the Tdarr cache live
on fast storage in `/scratch/{incomplete,transcode}`.

## Services

| Service | Port | Runs as |
|---|---|---|
| Plex | 32400 | native |
| Sonarr / Radarr / Bazarr | 8989 / 7878 / 6767 | native |
| Jackett (+ FlareSolverr on localhost:8191) | 9117 | native |
| qBittorrent | 8080 | native |
| Seerr | 5055 | native |
| Tdarr | 8265 | native, GPU node |
| Cleanuparr / Pulsarr / Maintainerr | 11011 / 3003 / 6246 | podman containers |
