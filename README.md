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

## Services

| Service                                    | Port                       | Runs as                                         |
|--------------------------------------------|----------------------------|-------------------------------------------------|
| Plex                                       | 32400                      | native                                          |
| Media Preview Generator                    | 8280                       | Podman, NVIDIA GPU                              |
| Sonarr / Radarr / Bazarr                   | 8989 / 7878 / 6767         | native                                          |
| Jackett (+ FlareSolverr on localhost:8191) | 9117                       | native                                          |
| qBittorrent                                | 8080                       | native                                          |
| Tdarr                                      | 8265 (UI), 8266 (server)   | native, GPU node                                |
| Cleanuparr                                 | 11011                      | podman container                                |
| Pulsarr                                    | 3003                       | podman container                                |
| Maintainerr                                | 6246                       | podman container                                |
| Immich (photos.steenblik.ch)               | 2283 (localhost)           | native, ML on 3004 as a podman CUDA container   |
| Paperless-ngx (documents.steenblik.ch)     | 28981 (localhost)          | native, + Tika 9998, Gotenberg 3001, PostgreSQL |
| Forgejo (git.steenblik.ch)                 | 3000 (localhost), SSH 2222 | native                                          |
| Forgejo runner                            | —                          | native, Podman jobs with per-job Docker-in-Docker |
| MicroBin (notes.steenblik.ch)              | 8081 (localhost)           | native                                          |
| CoolerControl                              | 11987 (localhost)          | native                                          |
| Dashboard (server.steenblik.ch)            | 5180 / 5181 (localhost)    | native, from the `server-dashboard` flake       |
| node_exporter                              | 9100 (localhost)           | native                                          |
| Prometheus / Alertmanager (mails alerts)   | 9090 / 9093 (localhost)    | native                                          |
| Grafana (grafana.internal.steenblik.ch)    | 3002 (localhost)           | native                                          |
| Tailscale (exit node)                      | —                          | native                                          |
| Ollama + Open WebUI (ai.steenblik.ch)      | 11434 / 8082 (localhost)   | native, Ollama on the RTX 3060                  |

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

## Music Assistant and Bluetooth audio

`host.music-assistant.enable` starts native systemd services for Music Assistant
and Sendspin Bluetooth Bridge. Music Assistant comes from its independently locked
`nixpkgs-music-assistant` unstable input (currently 2.10.6). The bridge is not in
Nixpkgs: `packages/sendspin-bt-bridge.nix` packages release 2.76.4 using Python and
GStreamer dependencies from the independently locked `nixpkgs-sendspin` unstable
input. Its upstream configuration/runtime tests and Sendspin/GStreamer checks run
during the build. Both versions use aiosendspin 9.1.1. BlueZ, system-wide PipeWire
and WirePlumber run natively, without a desktop login. This stack uses no containers.
Bluetooth audio roles are restricted to A2DP to prevent fallback to hands-free call audio.
Soloist's runtime downloads use `nix-ld` and the PulseAudio client library to run
on NixOS. Music Assistant's state directory allows execution so its downloaded
Soloist binary can start inside the service sandbox.
The service also exposes the PulseAudio client library to Python's ctypes loader.
The syscall filter permits `setresuid` and `capset` for the private PulseAudio
capture daemon's startup cleanup.

The UIs use the existing internal wildcard DNS and certificate:

- `https://music.internal.steenblik.ch` — Music Assistant
- `https://sendspin.internal.steenblik.ch` — Bluetooth bridge

nginx restricts both to LAN and Tailscale clients. The backend UI ports 8095 and
8098 are not opened to the LAN. TCP 8097 (audio streams), TCP 8927 (Sendspin) and
UDP 5353 (mDNS discovery) are allowed from `host.lanCidr`. Spotify Connect chooses
a random TCP listener, so TCP 32768–60999 (the server's ephemeral port range) is
also allowed from that LAN. This permits LAN access to other services listening
in that range too; it does not grant access from the internet. The bridge and Home
Assistant connect to Music Assistant locally. Bluetooth audio uses the host's
system PulseAudio-compatible socket, with BlueZ control over the system D-Bus.

### Before applying

- Attach a Linux-supported Bluetooth adapter within range of the Sony. The server
  had `hci0` during configuration; it still needs testing with the speaker.
- Keep the Sony on its supplied power adapter and disable Auto Standby in Sony
  Music Center for continuous availability.
- Have the server sudo password available for the deployment command above.
  Initial application does not need Spotify credentials or the speaker's address.

State directories `/var/lib/music-assistant` (systemd DynamicUser, backed by
`/var/lib/private/music-assistant`) and `/var/lib/sendspin` are created
automatically. No ZFS datasets need creating first. They are not dedicated
snapshotted datasets; BlueZ also keeps pairing state under `/var/lib/bluetooth`.
The initial bridge configuration is copied only when absent, so rebuilds preserve
UI changes, pairings and credentials. Keep these runtime files out of Git.

### After applying

1. Open Music Assistant, create its administrator account and verify the Sendspin
   player provider is enabled. In its webserver settings, set the base URL to
   `https://music.internal.steenblik.ch` if it advertises its direct HTTP address.
2. Open the bridge UI, put the Sony into pairing mode, scan and pair it. Select
   the adapter and save the speaker as a player. The initial Music Assistant URL
   is `http://127.0.0.1:8095`; authorize the bridge through its Music Assistant
   configuration page. Restart the bridge from its UI if prompted.
3. In Music Assistant, add the **Spotify Connect** plugin and select the Sony
   player under Connected players. The recommended Soloist engine requires a
   Spotify Premium account to create the personal API key during setup; follow
   its authorization flow. Keep the phone and server on the same LAN for
   discovery. The Spotify music provider is optional for browsing the library
   from Music Assistant; it is separate from Spotify Connect discovery. Native
   Nixpkgs builds do not include upstream's shared service credentials. If using
   the Spotify music provider, supply your own Spotify client ID through
   `systemd.services.music-assistant.environment.MASS_APP_VAR_SPOTIFY_CLIENT_ID`;
   Spotify Connect's Soloist API key is entered through the UI instead.
4. Add **Music Assistant** in Home Assistant's Devices & services, using
   `http://127.0.0.1:8095` and the credentials/token requested by the integration.
5. Play audio from Home Assistant and Spotify's device picker. Then restart the
   bridge and verify the Sony reconnects and plays again without a desktop login.

Check the deployed services and audio path with:

```sh
systemctl status bluetooth pipewire pipewire-pulse wireplumber music-assistant sendspin
sudo journalctl -u music-assistant -u sendspin -n 100
sudo env PULSE_SERVER=unix:/run/pulse/native pactl info
sudo env PULSE_SERVER=unix:/run/pulse/native pactl list short sinks
curl --fail http://127.0.0.1:8098/api/preflight
```

The sinks should include a `bluez_output.*` or `bluez_sink.*` device after pairing.
The bridge's preflight page checks Bluetooth, audio and Music Assistant readiness.
Update the Music Assistant and Sendspin Nixpkgs inputs independently, and test
protocol compatibility when updating either. Upstream:
[bridge installation](https://github.com/trudenboy/sendspin-bt-bridge/tree/v2.76.4),
[bridge compatibility](https://github.com/trudenboy/sendspin-bt-bridge/blob/v2.76.4/CHANGELOG.md),
[Spotify Connect setup](https://www.music-assistant.io/plugins/spotify-connect/).

## Forgejo CI

`forgejo-runner-docker.service` runs the Forgejo runner continuously, starts at boot
and restarts on exit. Its `docker` label uses an Ubuntu Actions image with Git,
Node and the Docker CLI, with one job at a time. The runner package has its own
`nixpkgs-forgejo-runner` input.

Podman launches the job containers. Image-building jobs start a Docker-in-Docker
service as shown below: the Docker CLI connects to that job's Docker daemon, so
Docker builds, BuildKit and pushes use Docker itself. There is no host Docker
daemon. Forgejo stops and removes job services on completion or cancellation;
Docker's memory is released and its local image/build cache is discarded. An
abrupt runner crash or forced kill can leave orphan containers; inspect
`sudo podman ps` after such a failure.

The host Podman socket is not mounted into jobs. Docker-in-Docker requires the
runner's privileged-container setting, which also applies to job containers;
this is still a trusted-code runner, not a security boundary. Register it only
for trusted repositories and do not run untrusted pull-request code on it.

### Registration

In the intended repository or organization's Settings → Actions → Runners,
choose Create new runner. Forgejo displays a UUID and token for that runner.
Both are required. Set the UUID directly in the `--uuid` argument in
`modules/services/forgejo.nix`; it is an identifier, not a secret. From this
repository, edit the encrypted token:

```sh
nix shell nixpkgs#sops -c sops secrets/secrets.yaml
```

Add this top-level YAML key in the editor, then save and close:

```yaml
forgejo-runner.env: |
  TOKEN=<runner-token>
```

The value is an environment file, not a bare token. Use the UUID and token from
the same runner. Commit the encrypted file
with `jj commit -m 'chore: add encrypted Forgejo runner credentials'`, then
deploy as described above. sops-nix decrypts it to the root-only
`/run/secrets/forgejo-runner.env`; systemd reads it for the runner. The service
connects using the supplied UUID and token, without running the deprecated
`register` command. Changing the secret restarts the runner. Its working data
is under `/var/lib/forgejo-runner`, and a private token file exists only while
the service runs, under `/run/forgejo-runner`. The secret must exist before
deployment. After deploying, check:

```sh
systemctl status forgejo-runner-docker
journalctl -u forgejo-runner-docker -n 50
```

Enable Actions in the repository's settings. Set repository secrets
`REGISTRY_USER` and `REGISTRY_TOKEN`; for Forgejo's registry the token needs
package write access. The runner's connection token is a separate credential.

### Build and push an image

In a repository with a Dockerfile, add `.forgejo/workflows/image.yml` based on
this example. Replace the image namespace/name with your own. The Docker service
is reachable only through the job network; it publishes no host ports.

```yaml
name: Build image
on:
  push:
    branches: [master]
jobs:
  image:
    runs-on: docker
    services:
      docker:
        image: docker.io/library/docker:28-dind
        env:
          DOCKER_TLS_CERTDIR: ""
    env:
      DOCKER_HOST: tcp://docker:2375
      IMAGE: git.steenblik.ch/jblik/my-app
    steps:
      - uses: https://data.forgejo.org/actions/checkout@v4
      - name: Wait for Docker
        run: timeout 60 sh -c 'until docker info >/dev/null 2>&1; do sleep 1; done'
      - name: Build and push
        env:
          REGISTRY_USER: ${{ secrets.REGISTRY_USER }}
          REGISTRY_TOKEN: ${{ secrets.REGISTRY_TOKEN }}
        run: |
          printf '%s' "$REGISTRY_TOKEN" | docker login git.steenblik.ch --username "$REGISTRY_USER" --password-stdin
          docker build --tag "$IMAGE:$GITHUB_SHA" .
          docker push "$IMAGE:$GITHUB_SHA"
```

The runner supports other jobs without a Docker service too; those jobs have no
Docker daemon. See the [Forgejo service-container reference](https://forgejo.org/docs/latest/user/actions/reference/#jobsjob_idservices)
and [Docker-in-Docker guidance](https://forgejo.org/docs/latest/admin/actions/docker-access/).

## AI

One Ollama serves every model, to:

- **Open WebUI** at `https://ai.steenblik.ch`: chat, behind its own login. Signup is off; the
  first account becomes the admin, who adds everyone else (Admin Panel → Users).
- **The API** at `https://ai.steenblik.ch/v1`, for CLIs and IDEs: OpenAI-compatible (`/v1/chat/completions`,
  `/v1/responses`, `/v1/embeddings`, `/v1/models`) and
  Anthropic-compatible (`/v1/messages`). It needs the `ai-api-key` secret, as
  `Authorization: Bearer <key>` or `x-api-key: <key>`.
- **Paperless**: tag/correspondent suggestions and chat with documents, on the `chat` model;
  its search index (`embedding` model) is rebuilt nightly at 02:10.

Immich keeps its own machine learning container: its CLIP search and face recognition need
vision models that Ollama doesn't serve.

### Models

`host.ai.models` in `hosts/nixos-server/default.nix`, as Ollama tags (<https://ollama.com/library>). `chat` is Open
WebUI's only selectable chat model and Paperless' model,
`embedding` is for document search in both, any other name (`code`) is only pulled for API
clients. Open WebUI's connection filter hides the coding and embedding models from its
model selector; embeddings remain available internally for document search. Deploy
pulls new tags and deletes dropped ones; `journalctl -fu ollama-model-loader` shows the
download. A model is loaded on first request and unloaded after 5 minutes idle, so the GPU
is free for Plex, Tdarr and Immich otherwise.

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
