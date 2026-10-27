# nixos-server

Ryzen 2700X, RTX 3060, 48 GB

## Layout

```
flake.nix                    nixosConfigurations.nixos-server, `versions`
packages.nix                 native application packages from independently locked inputs
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
`documents`, MicroBin as `notes`, the dashboard as `server`, Open WebUI as `ai`) are at `https://<app>.steenblik.ch`,
through 443 forwarded on the router; `cloudflare-dyndns` keeps their A records current.

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

### GitOps

Automatically deploying pushes to a protected `master` branch is reasonable once
changes have passed CI and review. Serialize deployments and deploy the exact
tested commit, including its lock file. Keep SSH access and a known-good generation
available for recovery.

Run activation from an independent systemd service or an external deployment host.
CI can validate/build the configuration and request a deployment, then finish; the
deployment service should fetch/build the selected revision before switching.
It needs its own Git credentials, including access to the private `server-dashboard`
flake input. A timer that polls the branch also works when Forgejo Actions is down.

Running `nixos-rebuild switch` directly in this server's Forgejo runner creates a
dependency cycle:

- A Forgejo restart temporarily interrupts polling, logs and job status reporting.
  The job process may continue, but successful reporting is not guaranteed.
- Changing the runner package, settings or unit can restart the runner and kill
  the deployment job. Graceful shutdown can instead wait for the very job whose
  rebuild is waiting for the runner to stop.
- Changes to the container runtime, networking or a reboot can interrupt the job
  or its connection even if the runner configuration is unchanged.

A failed CI job does not mean activation was rolled back: the server can already
be running the new generation. Verify the active revision and service health
independently. A system generation rollback also does not reverse Forgejo database
migrations; use the service's backups and upgrade guidance for those.

## Storage

- **Bulk:** one XFS filesystem per HDD at `/mnt/diskN`, merged by mergerfs into
  `/data`, SnapRAID parity once `parityFiles` is set.
- **Fast:** ZFS mirror `fast` on the two SATA SSDs. Service state under `/var/lib`, one
  dataset per service (`host.storage.fastDatasets.snapshot`), snapshotted hourly by
  sanoid; regeneratable data (Immich and Paperless thumbnails, transcodes) in `fastDatasets.noSnapshot`.

`/data`: `torrents/{tv,movies}`, `media/{tv,movies}` (imports are hardlinks).
`/scratch/{incomplete,transcode}` (NVMe, off the pool): in-progress downloads and the
Plex/Tdarr transcode cache.

Plex's generated `Media` directory is bind-mounted from `/data/plex-media` on the
HDDs. Media Preview Generator runs in Podman with the RTX 3060; its UI is on port 8280.

## Maintenance Window

The host explicitly sets `host.maintenance.window = { start = "01:45"; end = "05:30"; };`
in the server timezone; there are no fallback times. `host.maintenance.enable` defaults to
`false` and provides the default enable value for each task:

- `host.maintenance.keepCool`
- `host.maintenance.qbittorrent`
- `host.maintenance.tdarr`
- `host.maintenance.mediaPreviewGenerator`

Each task has `enable` and `window` options. Its window inherits the shared window.
For example, `host.maintenance.enable = true;` enables all tasks, while
`host.maintenance.tdarr.enable = false;` disables only Tdarr maintenance. An explicit
per-task enable value overrides the global default. Tasks disabled in Nix remain disabled
regardless of the Home Assistant controls. Home Assistant must be enabled for scheduling.

Home Assistant owns maintenance through Nix-managed helpers and automations in
`modules/services/maintenance/home-assistant.nix`:

- `input_boolean.server_maintenance` runs enabled tasks immediately, outside their scheduled windows.
  Presence automations can turn it on when everyone leaves and off when someone returns, using
  `input_boolean.turn_on` and `input_boolean.turn_off`. It restores its previous state on restart.
- `input_boolean.server_maintenance_schedule` enables daily scheduling independently of that switch.
  Turn both switches off to stop all maintenance work.
- `input_datetime.server_maintenance_start` and `input_datetime.server_maintenance_end` edit the
  shared daily window in the server timezone.
- Each task (`keep_cool`, `seeding`, `tdarr`, `previews`) has a
  `input_boolean.server_maintenance_<task>_inherit` helper. Turn it off to use that task's
  `input_datetime.server_maintenance_<task>_start` and `_end` helpers instead.

A task runs when the immediate switch is on **or** its enabled schedule is inside its window.
Turning the immediate switch off returns to scheduled behavior; it does not interrupt an active
scheduled window. Equal start/end times disable a window; an earlier end crosses midnight.
Time helpers and inheritance switches initialize from Nix at every Home Assistant restart;
the schedule enable switch initializes to on. Add these helpers to a Home Assistant dashboard
for editing. The existing UI-managed `automations.yaml` remains available for presence rules.

Home Assistant reconciles tasks on startup, helper changes, and window boundaries. It writes each
requested state atomically under `/var/lib/server-maintenance/` and starts the existing task oneshot
through narrowly scoped polkit permissions. Application startup and torrent-completion hooks read
that same local state; before the first state is written, maintenance is off. Last requested states
survive restarts. Failed task services retry after ten seconds. Home Assistant must stay running for
schedule boundaries; the server dashboard is no longer involved.

The media tasks each have a `default.nix` and `maintenance.py` under `modules/services/media/`.
Shared task launchers live in `modules/services/maintenance/`. Keep cool's script and configuration
live together in `modules/hardware/fans/`. Manual fan controls remain in the dashboard's Fans card.
Manual changes clear maintenance ownership through a separate invocation of the fan script, so
later reconciliation of the same active period preserves the manual choice. Ownership state under
`/var/lib/coolercontrol-maintenance/` survives service restarts.

Separate task services pause/unpause the Tdarr node, set preview CPU workers to
`host.maintenance.mediaPreviewGenerator.cpuWorkers` (default 2) or zero, and restrict completed torrents
to active maintenance periods. No maintenance polling timers are used.

Tdarr and preview workers finish current files when paused/reduced; preview GPU workers stay
available. The preview API's CPU count control requires a single dedicated CPU worker group; split
or mixed CPU/GPU groups must be adjusted in the preview application's Workers settings. The task
service reads the preview application's existing `auth.json` token locally, without exposing it to the
dashboard. Keep cool retains manual fan-mode ownership within a window.

qBittorrent runs its completion launcher as `qbittorrent`, reading the current maintenance state
rather than embedding window times in the completion command. Reconciliation runs as the same user
through the existing host-side WebUI proxy. Completion hooks use the VPN namespace's local WebUI
and need no dashboard connectivity. A shared lock and `seeding-stopped.json` live in the
existing writable `qBittorrent` profile subdirectory; this operational ownership state survives
restarts and is separate from schedule overrides. Only torrents stopped by the script are resumed;
manual stops and ratio/time limits remain respected. There is no completion marker or systemd path
watch, and qBittorrent's sandbox is unchanged. Applications may still save their own settings.

The server configuration and dashboard changes must be deployed together. For local validation,
use `--override-input server-dashboard path:/Users/jblik/projects/server-dashboard`; the checked-in
flake input continues to reference the published dashboard revision.

## Services

| Service                                    | Port                       | Runs as                                           |
|--------------------------------------------|----------------------------|---------------------------------------------------|
| Plex                                       | 32400                      | native                                            |
| Media Preview Generator                    | 8280                       | Podman, NVIDIA GPU                                |
| Sonarr / Radarr / Bazarr                   | 8989 / 7878 / 6767         | native                                            |
| Jackett (+ FlareSolverr on localhost:8191) | 9117                       | native                                            |
| qBittorrent                                | 8080                       | native                                            |
| Tdarr                                      | 8265 (UI), 8266 (server)   | native, GPU node                                  |
| Cleanuparr                                 | 11011                      | podman container                                  |
| Pulsarr                                    | 3003                       | podman container                                  |
| Maintainerr                                | 6246                       | podman container                                  |
| Immich (photos.steenblik.ch)               | 2283 (localhost)           | native, ML on 3004 as a podman CUDA container     |
| Paperless-ngx (documents.steenblik.ch)     | 28981 (localhost)          | native, + Tika 9998, Gotenberg 3001, PostgreSQL   |
| Forgejo (git.steenblik.ch)                 | 3000 (localhost), SSH 2222 | native                                            |
| Forgejo runner                             | —                          | native, Podman jobs with per-job Docker-in-Docker |
| MicroBin (notes.steenblik.ch)              | 8081 (localhost)           | native                                            |
| CoolerControl                              | 11987 (localhost)          | native                                            |
| Dashboard (server.steenblik.ch)            | 5180 / 5181 (localhost)    | native, from the `server-dashboard` flake         |
| node_exporter                              | 9100 (localhost)           | native                                            |
| Prometheus / Alertmanager (mails alerts)   | 9090 / 9093 (localhost)    | native                                            |
| Grafana (grafana.internal.steenblik.ch)    | 3002 (localhost)           | native                                            |
| Tailscale (exit node)                      | —                          | native                                            |
| Ollama + Open WebUI (ai.steenblik.ch)      | 11434 / 8082 (localhost)   | native, Ollama on the RTX 3060                    |

## VPN and torrent monitoring

With the dashboard and media stack enabled, `speedtest-nordvpn.timer` runs an
Ookla speedtest hourly, offset by 30 minutes from the host speedtest. It runs
inside qBittorrent's network namespace and binds to `nordvpn`, using the same
VPN DNS configuration. To run it manually after deploying:

```sh
sudo systemctl start speedtest-nordvpn.service
journalctl -u speedtest-nordvpn -n 50
```

Grafana's [NordVPN dashboard](https://grafana.internal.steenblik.ch/d/nordvpn)
compares VPN and host speeds and shows VPN latency, jitter, packet loss, and the
age of the last result.

The [qBittorrent dashboard](https://grafana.internal.steenblik.ch/d/qbittorrent)
shows transfer rates, session and all-time totals, share ratio, torrent counts by
state, remaining downloads, free download space, peers, DHT nodes, and connection
status. `qbittorrent-metrics.timer` collects every 30 seconds through the local
API inside the VPN namespace, using the API key already managed in qBittorrent's
profile. No additional credentials or public metrics port are needed. Both
collectors publish through node_exporter's textfile collector. If a collection
fails, its last successful result remains; check the age panels and service
journals when interpreting old readings.

## Home Assistant

Home Assistant runs natively through `services.home-assistant`, enabled by
`host.home-assistant.enable`. Nix manages the service, integration dependencies,
base configuration and HomeKit Bridge. Pairings and credentials are managed in
the UI and stored under `/var/lib/hass`; this directory is not yet a dedicated
snapshotted ZFS dataset.

Matter Server runs natively alongside Home Assistant, with persistent pairings
under `/var/lib/private/matter-server`. In Home Assistant's Matter integration,
use `ws://127.0.0.1:5580/ws`. The WebSocket endpoint listens only on localhost.
Home Assistant and Matter Server have independent `nixpkgs-home-assistant` and
`nixpkgs-matter-server` inputs.

TCP 8123 (UI), TCP 21063 (HomeKit), UDP 5353 (mDNS discovery) and UDP 5540 (Matter)
are allowed from `host.lanCidr`. mDNS and Matter are also allowed from IPv6
link-local and unique-local addresses for Thread devices. Keep the server, hubs
and iPhone on the same LAN for pairing; Thread devices need IPv6 connectivity
through a Thread border router.

### Chromebook display

The Chromebook automations keep the Companion app awake and control visibility
through screen brightness. Below 10 lux for ten seconds, or when everyone leaves
home, `script.chromebook_sleep` sets brightness to 0. Above 15 lux for two
seconds while someone is home, `script.chromebook_wake` restores brightness to
255 (100%). Between 10 and 15 lux, brightness stays unchanged. Startup and
presence changes also apply the existing light and presence conditions.
When `light.monkey` is on, brightness is always 100%, regardless of presence or
light level. Turning Monkey off reapplies the dark-room and away conditions.

Disable automatic brightness on the Chromebook. Both scripts enable
keep-screen-on; neither changes the screen timeout or locks the device.

### Dashboard cards

Home Assistant and its custom integrations use the independently locked
`nixpkgs-home-assistant` unstable input. Nix installs Atomic Calendar Revive,
Flightradar24 Card, and Music Assistant Player Card, plus the Flightradar24 and
Music Assistant Queue Actions integrations. Music Assistant Player Card is packaged
from its pinned release asset in `packages/mass-player-card.nix`; the other cards
above come from Nixpkgs. HACS is not needed.

After deploying with the command above:

1. In **Settings → Devices & services → Add integration**, add **Flightradar24**
   and configure the centre and radius of the monitored area.
2. Configure the official **Music Assistant** integration as described below.
   Accept discovery of **Music Assistant Queue Actions**, or add it through **Add integration** if it is not discovered.
3. Configure your calendar provider in Home Assistant so a `calendar.*` entity
   exists. Providers with additional Python dependencies also need their integration
   name in `services.home-assistant.extraComponents`.
4. Reload the browser, edit your dashboard and select **Add card**. Search for **Atomic Calendar Revive**,
   **Flightradar24 Card**, or **Music Assistant Player Card**.
   Select your calendar, the Flightradar24 current-in-area sensor, or a Music Assistant
   player entity respectively. The music card includes a queue tab and queue controls.

Nix registers JavaScript resources under `/local/nixos-lovelace-modules/` and manages
them in YAML; dashboard layouts remain editable in the UI. Add resource declarations
in Nix rather than the Resources UI, and avoid installing duplicate copies through
HACS. Update the packaged integrations and cards with
`nix flake update nixpkgs-home-assistant`; update the local music card's version and
asset hash separately.

### AI Models

`host.ai.models` in `hosts/nixos-server/default.nix`, as Ollama tags (<https://ollama.com/library>). `chat` is Open
WebUI's only selectable chat model and Paperless' model,
`embedding` is for document search in both, any other name (`code`) is only pulled for API
clients. Open WebUI's connection filter hides the coding and embedding models from its
model selector; embeddings remain available internally for document search. Deploy
pulls new tags and deletes dropped ones; `journalctl -fu ollama-model-loader` shows the
download. A model is loaded on first request and unloaded after 5 minutes idle.

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

Each standalone native application has its own `nixpkgs-<app>` input and lock entry, including
applications on stable. The `nixpkgs` input controls the OS and shared system tools.
The dashboard already has its own `server-dashboard` input. Container images are
configured separately in `modules/services/media/containers.nix`; Immich's ML image
follows its application version.

Update only the application you choose:

```sh
nix flake update nixpkgs-paperless
nix eval --json .#versions | jq
```

Paperless' package, NixOS service module, Tika and Gotenberg use that same input,
while Gotenberg's Chromium and LibreOffice helpers use the system packages.
PostgreSQL and Redis keep separate pins because they are shared with Immich. Once Paperless' locked
revision includes the torchcodec test fix, remove the `extraPythonPackageOverrides`
override in `packages.nix`. Immich and every other application keep their existing
locks. Tdarr's server and node share `nixpkgs-tdarr`; their explicit version/hash
overrides remain until that input provides at least 2.91.01.

Use `nix flake update nixpkgs` to update the OS without advancing application pins.
Avoid an unqualified `nix flake update` unless you intend to update every input.
Build and deploy as described above after checking the selected version.

### Back to plain nixpkgs

The goal is no custom version or build overrides. Independent application pins stay
so each application can be updated separately. Once stable nixpkgs has caught up:

1. Update only the OS input: `nix flake update nixpkgs`, or move `nixpkgs` in
   `flake.nix` to the next release (`nixos-26.11`) once it's out.
2. `nix eval --json .#versions | jq`: an application can move to stable when its
   `nixpkgs` version is the same or newer than `here`. Never go to an older one.
3. Change the application's input URL to that stable branch and run
   `nix flake update nixpkgs-<app>`. Keep its package selection in `packages.nix`, but
   remove any custom overrides stable no longer needs: the Tdarr helper or
   Paperless' `torchcodec` fix. For Paperless, remove the `disabledModules`/`imports`
   lines in `modules/services/paperless/default.nix` once the OS module handles 3.x.
4. Build and deploy (see Deploy). Check the service starts and its journal shows no
   database migration errors. Commit.
