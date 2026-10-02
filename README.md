# nixos-server

Ryzen 2700X, RTX 3060, 32 GB

Progress and next steps: [docs/MIGRATION.md](docs/MIGRATION.md).

## Layout

```
flake.nix                    nixosConfigurations.nixos-server, `versions`
packages.nix                 every package not taken from nixos-26.05 as is
hosts/nixos-server/          hardware config + site knobs (disks, subnet, what's enabled)
modules/options.nix          the `host.*` knobs
modules/system/              boot, network/firewall/wake-on-LAN, nix, users, ssh, tailscale
modules/hardware/            nvidia driver, fan2go fan control, RGB off
modules/storage/             mergerfs union, snapraid parity, zfs fast pool, spin-down
modules/services/            media stack, *arr, forgejo, nginx reverse proxy, AI (off)
```

Firewall: SSH, Plex, HTTPS (443) and Forgejo SSH (2222) are open; every other UI is LAN-only (`host.lanCidr`)
or over Tailscale (`tailscale0` is trusted).

## Reverse proxy

nginx serves every UI at `https://<app>.internal.steenblik.ch`: the wildcard record points
at the tailnet IP and nginx only allows LAN and tailnet sources. Hosts in `public`
(`modules/services/proxy.nix`: Forgejo as `git`) are at `https://<app>.steenblik.ch`, through
443 forwarded on the router; `cloudflare-dyndns` keeps their A records current.

Certificates come from Let's Encrypt via Cloudflare DNS-01, so port 80 stays closed.

## Secrets

sops-nix: `secrets/secrets.yaml` is committed encrypted, each key becomes
`/run/secrets/<key>` on the server, decrypted with its SSH host key. Recipients (your age
key and the server's) are in `.sops.yaml`. Edit with
`nix shell nixpkgs#sops -c sops secrets/secrets.yaml`, then `jj commit` and deploy.

## Deploy

Edit on the Mac and `jj commit` (the flake only sees committed files), then build and
switch on the server:

```sh
nix run nixpkgs#nixos-rebuild -- switch --flake .#nixos-server --target-host nixos-server --build-host nixos-server --sudo --ask-sudo-password
```

A bad generation can be rolled back with `sudo nixos-rebuild switch --rollback`, or by
picking an older entry in the boot menu.

## Storage

- **Bulk:** one XFS filesystem per HDD at `/mnt/diskN`, merged by mergerfs into
  `/data`, SnapRAID parity once `parityFiles` is set. Currently only `disk1` (10 TB),
  no parity, holding unraid's movies and TV.
- **Fast:** ZFS mirror `fast` on the two SATA SSDs. Service state under `/var/lib`, one
  dataset per service (`host.storage.fastDatasets`), snapshotted hourly by sanoid.

`/data`: `torrents/{tv,movies}`, `media/{tv,movies}` (imports are hardlinks).
`/scratch/{incomplete,transcode}` (NVMe, off the pool): in-progress downloads and the
Plex/Tdarr transcode cache.

## Services

Plex, the *arr apps and Tdarr run on the state imported from unraid; Pulsarr started
fresh.

| Service | Port | Runs as |
|---|---|---|
| Plex | 32400 | native |
| Sonarr / Radarr / Bazarr | 8989 / 7878 / 6767 | native |
| Jackett (+ FlareSolverr on localhost:8191) | 9117 | native |
| qBittorrent | 8080 | native |
| Tdarr | 8265 | native, GPU node |
| Cleanuparr | 11011 | podman container |
| Pulsarr | 3003 | podman container |
| Maintainerr | 6246 | podman container |
| Forgejo (git.steenblik.ch) | 3000 (localhost), SSH 2222 | native |
| Dashboard (server.steenblik.ch) | 5180 / 5181 (localhost) | native, from the `server-dashboard` flake |
| node_exporter | 9100 (localhost) | native |
| Tailscale (exit node) | — | native |

## Package versions

Services whose database was imported from unraid must never run an older version than
unraid did, or they can't open it. Where nixos-26.05 is behind, `packages.nix` takes the
package from nixpkgs-unstable (Plex, Radarr, Bazarr, Immich, Paperless) or pins the
version itself (Tdarr). It is the only place that does; the modules just use `pkgs`.

```sh
nix eval --json .#versions | jq   # each package: version here, version in nixos-26.05
```

### Back to plain nixpkgs

The goal is no overrides. Once nixpkgs has caught up with a package, it goes back to the
nixpkgs version:

1. Update the inputs: `nix flake update`, or move `nixpkgs` in `flake.nix` to the next
   release (`nixos-26.11`) once it's out. Commit.
2. `nix eval --json .#versions | jq`: a package can drop out of `packages.nix` when its
   `nixpkgs` version is the same or newer than `here`. Never go to an older one.
3. Delete its entry from `packages.nix`, with what only it needed: the Tdarr helper,
   Paperless' `torchcodec` fix, and for Paperless also the `disabledModules`/`imports`
   lines in `modules/services/paperless/default.nix` once the release's module handles 3.x.
4. Build and deploy (see Deploy). Check the service starts and its journal shows no
   database migration errors. Commit.
5. When `packages.nix` is empty: delete it, the `overlay` and `versions` in `flake.nix`,
   the `nixpkgs-unstable` input and `pkgs-unstable`, then `nix flake lock` and deploy.
