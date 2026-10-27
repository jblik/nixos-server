# Local Flight Simulator setup

Implementation has started with the local graphical/audio/Steam configuration.
The workload lifecycle and cleanup tools in [the implementation plan](../../../FLIGHT-SIMULATOR-PLAN.md)
are still pending. This configuration is **not ready for gaming acceptance or
deployment**: starting Steam currently does not pause any server workload.

`host.gaming.enable` defaults to false and is enabled for `nixos-server` in the
checked-in host configuration. No running system has been switched. The module
adds Steam's normal input rules, 32-bit graphics/audio support, Openbox with manual
`startx`, PipeWire, and local audio/input diagnostic tools. It keeps the existing
NVIDIA driver, SSH, Tailscale, cooling and monitoring configuration. There is no
display manager, automatic login, session at boot, X11 TCP listener or additional
firewall opening. Steam Remote Play and local game transfer firewall options
remain disabled.

## Later local setup

These steps are for an agreed deployment and acceptance session after the lifecycle
has been implemented. Do not execute them during repository implementation.

1. Connect a monitor directly to the RTX 3060, plus keyboard, mouse and yoke. Log
   in as `jblik` on the physical console with the existing local password. Run
   `startx` explicitly. The generated system xinitrc selects Openbox and manages
   the NixOS graphical user target. A personal `~/.xinitrc` or `XINITRC` overrides
   that script; inspect any override before testing. Open `xterm` from Openbox's
   menu. Steam and the game must run as `jblik`.
2. Run `vulkaninfo --summary` and inspect `wpctl status`. Use `pavucontrol` to
   choose the NVIDIA HDMI/DisplayPort output and its profile. Actual connector
   names, sink IDs and working audio have not been established.
3. Check `df -h /` before installing anything. In Steam's Storage settings, add
   `/var/lib/flight-simulator/library` and select it for Flight Simulator 2024
   (Steam app ID `2537590`). The directory is created as `jblik:users`, mode
   `0750`, on the root NVMe outside `/scratch`. The 200 GiB initial budget is a
   planning allowance, not a reservation or quota. Recheck headroom as scenery
   and add-ons grow; never automatically remove server data to make room.
4. Use the Steam edition, sign into Steam and Microsoft interactively, and select
   a Steam-managed Proton release in the game's Properties → Compatibility.
   Try the current stable release first, then Experimental if needed. Record the
   actual version and any demonstrated issue before introducing launch flags
   or a custom Proton build. Purchases and installation remain user actions.
5. Use `lsusb` and `evtest` to identify the actual Linux yoke axes and buttons.
   Record vendor/product IDs and any separate pedals or throttle. A throttle
   attached to the yoke may be part of the same device. Check normal local-user
   access before considering a device-specific udev rule. Do not add blanket
   input-group membership or world-writable permissions. If raw axes are absent
   in the simulator, test Steam Input remapping before calibrating bindings.
6. Begin at 1080p with moderate settings. Measure an actual flight before tuning
   performance, cooling or graphics. Linux input recognition alone does not
   establish Proton/game compatibility.

`gaming start`, `gaming stop`, `gaming status` and `gaming recover` do not exist
yet. The next implementation must gate Steam startup on successful workload
preparation and track the entire Steam session. Exiting a flight can leave Steam
running; the eventual managed session must end explicitly or on logout/failure.
Launching Steam manually will remain outside that workload coordination.

## Workload integration still required

No service pause, restart, masking, fan-mode change or application setting change
has been implemented or exercised. The intended gaming behavior is:

| Service | Required behavior before a managed Steam session |
| --- | --- |
| `tdarr-node-main.service` | Pause, drain current files, then stop the node; keep `tdarr-server.service` available |
| `podman-media-preview-generator.service` | Drain CPU and GPU work, then stop the container |
| `ollama.service` | Stop inference; Open WebUI may remain running |
| `immich-server.service`, `podman-immich-machine-learning.service` | Stop GPU-capable photo processing; photo downtime is acceptable |
| `plex.service` | Stay running with GPU decoding/encoding disabled; drain existing GPU transcodes |
| `qbittorrent-seeding-schedule.service` and completion hook | Apply inactive maintenance without losing torrent-stop ownership; downloads/VPN remain running |
| `coolercontrol-maintenance.service` | End only the maintenance-owned fan override; retain normal curves/telemetry and manual fan choices |

The existing maintenance request is immediate **or** scheduled. Do not clear Home
Assistant helpers or requested-state files to pause work. No new maintenance
activation is expected during play, per the agreed assumption. Service-start
hooks and retrying maintenance oneshots still need narrow coordination, and the
torrent completion hook must continue to enforce inactive seeding while gaming.
Restoration must reconcile the current Home Assistant calculation, preserve
manual pauses/stops, and report failure if reconciliation is unavailable.

Inspection notes for the lifecycle implementation:

- Tdarr's existing code uses `GET /api/v2/get-nodes` and
  `POST /api/v2/update-node`. Read-only inspection found `nodePaused`, `workers`
  and `workerLimits` on the configured `nixos-server-main` node. It was paused
  with an empty workers map; a busy worker's full state and drain transitions
  have not been observed. Process existence alone is not proof of idleness.
- Preview generator is pinned to `5.1.0`. Its
  [release source](https://github.com/stevezau/media_preview_generator/tree/53e14f9ffa9a136c9d0c47d4d1292dc203c4b2a5)
  exposes processing pause and worker status APIs. Global processing pause can
  freeze in-flight work; it is insufficient as a drain operation. The worker
  group policy API provides revision-based updates and retiring/busy capacity.
  Validate authentication, current configuration, complete drain detection and
  ownership restoration before implementing those calls. The preview auth file
  was not readable as `jblik`; no privileged API calls were attempted.
- Plex is native version `1.43.4.10903-e5521bd8c` on systemd `260.5`.
  `plex.service` reports `DevicePolicy=auto` without an explicit allow list.
  Live reversible device restriction is still unverified. Blocking new opens
  does not release existing GPU contexts. If that approach cannot satisfy the
  plan, verify the authenticated live hardware-acceleration setting against the
  installed version; do not edit its live preferences file. Plex's documented
  [hardware acceleration setting](https://support.plex.tv/articles/115002178853-using-hardware-accelerated-streaming/)
  takes effect without a server restart. CPU transcodes may compete for CPU
  during gaming; Direct Play and Direct Stream must remain available.
- Stopped services must stay stopped through dependency/start hooks and return
  only when gaming owned the stop. Journal transitions before applying them;
  recover failed preparation, logout, session failure and reboot without
  restarting Steam or retaining gaming inhibition.

## Storage inventory and removal still required

The dedicated library is the only game-related path created by this module.
After the later installation, record canonical paths, ownership and allocated
space for:

| Content | Expected location to verify after installation |
| --- | --- |
| Game installation and partial downloads | `library/steamapps/common`, `library/steamapps/downloading/2537590` and its app manifest |
| Per-game shader data | `library/steamapps/shadercache/2537590` |
| Proton prefix | `library/steamapps/compatdata/2537590` |
| Steam client, login, screenshots, logs and shared runtimes | Inspect `~/.local/share/Steam`, `~/.steam` and selected Steam libraries; do not treat them as game-exclusive |
| Simulator saves, bindings, scenery and rolling caches | Inspect the actual Proton prefix and any locations selected in-game; not established yet |

Paths above are setup expectations, not an authorized deletion list. Proton
`compatdata` can contain saves, settings and authentication and is not disposable
cache. Keep shared Proton builds and other apps separate from this game's data.

Cleanup commands are not implemented yet. Until they provide a dry-run inventory,
process/path/symlink checks and explicit confirmation, do not remove these paths
automatically. The eventual modes must distinguish regeneratable caches, Steam
uninstall plus explicitly selected residual game/user data, and full feature
removal after successful stop/recovery. Offer a user-directed export of local
saves and bindings before deletion; cloud sync is not a backup. Report allocated
space with `du` and `df -h /` before and after. Do not run global GC or remove
global Steam state as part of game cleanup.

## Verification record

Initial checks on 2026-10-27:

- Used the pinned OS nixpkgs revision
  `cd4ea8d57de16f4810bc5f14207bac45fbf19f67` without changing any lock entry.
- Repository `nix fmt` passed; enabled and disabled evaluations had no failed
  assertions. Full enabled system derivation evaluation passed.
- Generated `xinitrc` and `xserverrc` passed `bash -n`; Xorg arguments include
  `-nolisten tcp`. There is no `display-manager` unit.
- Gaming-disabled workload service configurations, firewall, packages and
  tmpfiles matched the parent revision. Enabled graphics kept the same NVIDIA
  driver and added no firewall ports.
- The first local X11 script build was unavailable because this Mac cannot run
  `x86_64-linux` builders. After server builds were authorized, copied the
  evaluated system derivation to the server's Nix store and built it there with
  `nix build --no-link`. The full system closure built successfully, including
  Steam, 32-bit NVIDIA userspace and the generated X11 scripts. Output:
  `/nix/store/lzg00lrjpgpivnxy6n5ymrvf0hqxrj1h-nixos-system-nixos-server-26.05.20261020.cd4ea8d`.
  Built X11 scripts passed `bash -n` on the server. The active generation was
  unchanged afterward and all seven inspected workload services remained active.
  No profile was switched and no activation script was executed.
- Read-only server inspection reported 317 GiB available on `/`. No yoke,
  keyboard, mouse, pedals or throttle were visible in USB product discovery;
  only the onboard AURA controller and host controllers were present.
- Actual display/audio, login dialogs, game compatibility, input permissions,
  flights and sustained-load cooling remain untested. Lifecycle/recovery and
  destructive cleanup checks await their implementations.
