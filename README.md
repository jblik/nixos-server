# nixos-server

Ryzen 2700X, RTX 3060, 48 GB

## Layout

```
flake.nix                    nixosConfigurations.nixos-server, `versions`
packages.nix                 every package not taken from nixos-26.05 as is
hosts/nixos-server/          hardware config + site knobs (disks, subnet, what's enabled)
modules/options.nix          the `host.*` knobs
modules/system/              boot, network/firewall/wake-on-LAN, nix, users, ssh, tailscale
modules/hardware/            nvidia driver, CoolerControl fan curves, RGB off
modules/storage/             mergerfs union, snapraid parity, zfs fast pool, spin-down
modules/services/            media stack, immich, paperless, forgejo, microbin, dashboard, nginx, AI
```

Firewall: SSH, Plex, HTTPS (443) and Forgejo SSH (2222) are open; every other UI is LAN-only (`host.lanCidr`)
or over Tailscale (`tailscale0` is trusted).

## Reverse proxy

nginx serves every UI at `https://<app>.internal.steenblik.ch`: the wildcard record points
at the tailnet IP and nginx only allows LAN and tailnet sources. Hosts in `public`
(`modules/services/proxy.nix`: Forgejo as `git`, Immich as `photos`, Paperless as
`documents`, MicroBin as `notes`, the dashboard as `server`, Open WebUI as `ai`) are at `https://<app>.steenblik.ch`, through
443 forwarded on the router; `cloudflare-dyndns` keeps their A records current.

Certificates come from Let's Encrypt via Cloudflare DNS-01, so port 80 stays closed.

## Secrets

sops-nix: `secrets/secrets.yaml` is committed encrypted, each key becomes
`/run/secrets/<key>` on the server, decrypted with its SSH host key. Recipients (your age
key and the server's) are in `.sops.yaml`. Edit with
`nix shell nixpkgs#sops -c sops secrets/secrets.yaml`, then commit and deploy.

## Deploy

Edit on the Mac and commit (the flake only sees committed files), then build and
switch on the server:

```sh
nix run nixpkgs#nixos-rebuild -- switch --flake .#nixos-server --target-host nixos-server --build-host nixos-server --sudo --ask-sudo-password
```

A bad generation can be rolled back with `sudo nixos-rebuild switch --rollback`, or by
picking an older entry in the boot menu.

## Storage

- **Bulk:** one XFS filesystem per HDD at `/mnt/diskN`, merged by mergerfs into
  `/data`, SnapRAID parity once `parityFiles` is set.
- **Fast:** ZFS mirror `fast` on the two SATA SSDs. Service state under `/var/lib`, one
  dataset per service (`host.storage.fastDatasets.snapshot`), snapshotted hourly by
  sanoid; regeneratable data (Immich and Paperless thumbnails, transcodes) in `fastDatasets.noSnapshot`.

`/data`: `torrents/{tv,movies}`, `media/{tv,movies}` (imports are hardlinks).
`/scratch/{incomplete,transcode}` (NVMe, off the pool): in-progress downloads and the
Plex/Tdarr transcode cache.

## Services

| Service                                       | Port                       | Runs as                                         |
|-----------------------------------------------|----------------------------|-------------------------------------------------|
| Plex                                          | 32400                      | native                                          |
| Sonarr / Radarr / Bazarr                      | 8989 / 7878 / 6767         | native                                          |
| Jackett (+ FlareSolverr on localhost:8191)    | 9117                       | native                                          |
| qBittorrent                                   | 8080                       | native                                          |
| Tdarr                                         | 8265 (UI), 8266 (server)   | native, GPU node                                |
| Cleanuparr                                    | 11011                      | podman container                                |
| Pulsarr                                       | 3003                       | podman container                                |
| Maintainerr                                   | 6246                       | podman container                                |
| Immich (photos.steenblik.ch)                  | 2283 (localhost)           | native, ML on 3004 as a podman CUDA container   |
| Paperless-ngx (documents.steenblik.ch)        | 28981 (localhost)          | native, + Tika 9998, Gotenberg 3001, PostgreSQL |
| Forgejo (git.steenblik.ch)                    | 3000 (localhost), SSH 2222 | native                                          |
| MicroBin (notes.steenblik.ch)                 | 8081 (localhost)           | native                                          |
| CoolerControl                                 | 11987 (localhost)          | native                                          |
| Dashboard (server.steenblik.ch)               | 5180 / 5181 (localhost)    | native, from the `server-dashboard` flake       |
| node_exporter                                 | 9100 (localhost)           | native                                          |
| Prometheus / Alertmanager (mails alerts)      | 9090 / 9093 (localhost)    | native                                          |
| Grafana (grafana.internal.steenblik.ch)       | 3002 (localhost)           | native                                          |
| Tailscale (exit node)                         | —                          | native                                          |
| Ollama + Open WebUI (ai.steenblik.ch)         | 11434 / 8082 (localhost)   | native, Ollama on the RTX 3060                  |

## AI

One Ollama serves every model, to:

- **Open WebUI** at `https://ai.steenblik.ch`: chat, behind its own login. Signup is off; the
  first account becomes the admin, who adds everyone else (Admin Panel → Users).
- **The API** at `https://ai.steenblik.ch/v1`, for CLIs and IDEs: OpenAI-compatible
  (`/v1/chat/completions`, `/v1/responses`, `/v1/embeddings`, `/v1/models`) and
  Anthropic-compatible (`/v1/messages`). It needs the `ai-api-key` secret, as
  `Authorization: Bearer <key>` or `x-api-key: <key>`.
- **Paperless**: tag/correspondent suggestions and chat with documents, on the `chat` model;
  its search index (`embedding` model) is rebuilt nightly at 02:10.

Immich keeps its own machine learning container: its CLIP search and face recognition need
vision models that Ollama doesn't serve.

### Models

`host.ai.models` in `hosts/nixos-server/default.nix`, as Ollama tags
(<https://ollama.com/library>). `chat` is Open WebUI's default and Paperless' model,
`embedding` is for document search in both, any other name (`code`) is only pulled. Deploy
pulls new tags and deletes dropped ones; `journalctl -fu ollama-model-loader` shows the
download. A model is loaded on first request and unloaded after 5 minutes idle, so the GPU
is free for Plex, Tdarr and Immich otherwise.

### Setup

1. Generate a key and add it as `ai-api-key` (see Secrets), then commit:
   ```sh
   openssl rand -hex 32
   nix shell nixpkgs#sops -c sops secrets/secrets.yaml
   ```
2. Create Open WebUI's dataset on the server:
   ```sh
   ssh -t nixos-server sudo zfs create -o mountpoint=legacy fast/open-webui
   ```
3. Deploy, open `https://ai.steenblik.ch` right away and create the admin account.

### Clients

The key is `sops -d --extract '["ai-api-key"]' secrets/secrets.yaml`.

- OpenAI-compatible (Continue, Zed, opencode, Codex, JetBrains AI, …): base URL
  `https://ai.steenblik.ch/v1`, the key as API key, a model tag as model.
- Claude Code:
  ```sh
  ANTHROPIC_BASE_URL=https://ai.steenblik.ch ANTHROPIC_AUTH_TOKEN=<key> \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3:8b claude --model qwen3-coder:30b
  ```

## Package versions

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
