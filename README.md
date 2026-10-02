# nixos-server

One NixOS box (Ryzen 2700X, RTX 3060, 32 GB) replacing the unraid server.
Progress and next steps: [docs/MIGRATION.md](docs/MIGRATION.md).

## Layout

```
flake.nix                    nixosConfigurations.nixos-server
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
(`modules/services/proxy.nix`: Seerr, Forgejo as `git`) are at `https://<app>.steenblik.ch`, through
443 forwarded on the router; `cloudflare-dyndns` keeps their A records current.

Certificates come from Let's Encrypt via Cloudflare DNS-01, so port 80 stays closed. The
Cloudflare token is the sops secret `cloudflare-dns-token` (token only); ACME gets it as
`CF_DNS_API_TOKEN` through a sops template.

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

Plex, Radarr and Bazarr come from nixpkgs-unstable, so they are never older than the
unraid versions their databases were imported from.

| Service | Port | Runs as |
|---|---|---|
| Plex | 32400 | native |
| Sonarr / Radarr / Bazarr | 8989 / 7878 / 6767 | native |
| Jackett (+ FlareSolverr on localhost:8191) | 9117 | native |
| qBittorrent | 8080 | native |
| Seerr | 5055 | native |
| Tdarr | 8265 | native, GPU node |
| Cleanuparr / Pulsarr / Maintainerr | 11011 / 3003 / 6246 | podman containers |
| Forgejo (git.steenblik.ch) | 3000 (localhost), SSH 2222 | native |
| Dashboard (server.steenblik.ch) | 5180 / 5181 (localhost) | native, from the `server-dashboard` flake |
| node_exporter | 9100 (localhost) | native |
| Tailscale (exit node) | — | native |
