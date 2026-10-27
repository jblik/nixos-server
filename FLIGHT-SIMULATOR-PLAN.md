# Flight Simulator on NixOS implementation plan

## Objective and execution boundary

Prepare Microsoft Flight Simulator 2024's Steam edition to run on NixOS through
Proton, using a monitor connected directly to the RTX 3060 and a Logitech flight
yoke connected by USB. Proton is a Windows compatibility layer, not a native
Linux game release. Game and yoke compatibility must be established later.

This replaces the Windows VM implementation plan. Do not implement libvirt,
Windows installation, VFIO, GPU driver handoff, USB passthrough, streaming or remote
desktop support. Linux retains the GPU and normal temperature monitoring.
Preserve existing SSH/Tailscale access for host administration and recovery.

Implement the repository changes autonomously, following the working agreement.
Keep changes local, commit completed verified subtasks with one-line conventional
`jj commit` messages, and never push or rewrite history. Match existing code and
module patterns. This task prepares implementation, not production deployment.

Live testing is a later phase. Do not deploy, reboot, stop server services, start
a graphical session or game, or download game content during implementation.
Formatting, evaluation and build checks remain required before code commits.
Record verification limitations and runtime inputs rather than guessing them.
Steam/Microsoft sign-in, purchases and game installation are later user actions;
never embed account credentials, automate purchases or weaken account security.

## Assumptions and observed hardware

The user explicitly permits assuming that maintenance mode will not be triggered
while gaming. Do not build a new maintenance-trigger suppression system, rewrite
Home Assistant automations, or introduce a cross-service maintenance lock merely
to handle that excluded case. Still pause work already running at session start
and restore normal behavior afterward. Existing service-start hooks and retries
need inspection so they do not accidentally undo the implemented pause.

Observed during earlier read-only inspection; recheck capacity before deployment:

| Item | Observation / decision |
|---|---|
| CPU | Ryzen 7 2700X, 8 cores / 16 threads |
| Memory | 48 GB reported in README; no fixed guest allocation needed |
| GPU | RTX 3060, existing proprietary NVIDIA driver |
| Display | HDMI/DisplayPort cable directly from GPU to monitor |
| Inputs | Keyboard, mouse and Logitech yoke connected to the server |
| NVMe | ADATA SX8200NP, 447.1 GiB physical capacity; 321 GiB available on root |
| Other storage | SATA SSD mirror: 139 GiB available; HDD union: about 8.2 TiB |
| Game | Steam app ID `2537590` (Flight Simulator 2024) |

Use the NVMe for the game and Proton data, outside `/scratch`. Budget up to
200 GiB initially, leaving roughly 121 GiB at observed usage for host growth and
scratch space. This is a planning budget, not reserved space or a new partition.
Downloaded scenery/add-ons can grow beyond it. Do not create VM disks or move
service datasets. The server currently has no configured graphical session.

## 1. Inspect the existing integration points

Read these before editing:

- `flake.nix`, `modules/options.nix`, `modules/system/default.nix`,
  `modules/system/users.nix`, `modules/hardware/nvidia.nix`.
- `modules/services/maintenance/{default.nix,service.nix,command.py,home-assistant.nix}`.
- `modules/services/media/tdarr/{default.nix,maintenance.py}` and
  `modules/services/media/media-preview-generator/{default.nix,maintenance.py}`.
- `modules/services/media/qbittorrent/{default.nix,maintenance.py}`,
  `modules/services/ai.nix`, `modules/services/immich.nix`, and
  `modules/services/media/plex.nix`.
- `modules/hardware/fans/{default.nix,maintenance.py}` and its shell scripts.

Inspect the locked nixpkgs modules for exact Steam, graphical-session, audio and
service options. Resolve actual evaluated unit names, container lifecycle and
dependencies rather than assuming them. Do not update the lock file or add a new
flake dependency. Read-only hardware/service discovery over SSH is allowed.

Important existing behavior: the maintenance immediate switch and scheduled window
are ORed together. Switching off the immediate switch alone does not necessarily
pause a task. Tdarr's pause finishes current files; preview maintenance only sets
CPU worker count, leaving GPU workers available. qBittorrent completion/start
hooks use the shared maintenance command. Fan maintenance tracks whether it owns
the mode; manual fan choices must remain respected.

## 2. Add a small local gaming configuration

Use one dedicated module, for example `modules/system/gaming/default.nix`, with
supporting scripts alongside it, imported through the existing system layout.
Add `host.gaming.enable` following existing option conventions and enable it for
this host in the checked-in configuration. Do not deploy it in this phase.

Enable the existing NixOS Steam module and the required NVIDIA/Vulkan userspace
including 32-bit support. Keep the current NVIDIA driver unless a demonstrated
compatibility issue requires a separate decision. Use Steam-managed Proton;
document how to select the stable release or Experimental for this game. Do not
blindly copy old launch flags, disable IPv6 globally, or add a custom Proton build
before testing identifies a need.

Provide a minimal local graphical session for `jblik`, plus PipeWire audio and
HDMI/DisplayPort output selection. A small X11 session is an acceptable initial
choice for the existing NVIDIA setup; verify its pinned module interfaces rather
than adding a full desktop suite. Avoid Gamescope, HDR, VR and performance tuning
as initial requirements. Use normal local login and explicit session startup;
do not enable automatic login or start the gaming session at boot.

The direct monitor, keyboard and mouse must support Steam login, Microsoft login
dialogs and settings. No Sunshine, Moonlight, VNC/SPICE, guest Tailscale, streaming
ports, remote display listeners or firewall changes for Steam Remote Play.
Steam/game processes run as `jblik`, never root. Keep existing sudo policy and
grant only narrowly scoped, authenticated lifecycle operations if needed.

## 3. Implement an explicit gaming session lifecycle

Provide a small interface equivalent to `gaming start`, `gaming stop`,
`gaming status` and `gaming recover`. These names describe intended commands;
they do not exist yet. Coordinate a root-owned systemd lifecycle service with the
user's local session; do not treat a launcher shell trap as the only cleanup path.

Start must finish workload preparation successfully before allowing the managed
Steam session to launch. Document that manually launching Steam outside this path
does not activate gaming mode. Track the full managed session, not the short-lived
`steam -applaunch` launcher: Steam may detach and the game is a descendant process.
Exiting the game can leave Steam open; make the session boundary and explicit stop
action clear. Restore server operation on logout, session failure and failed start.

Serialize transitions and record exactly what the session changed, including
initial unit states and any workload pause/fan ownership state. Use root-owned
runtime state and only the persistent recovery journal needed for interrupted
transitions. Make cleanup idempotent and bounded. Avoid changing global service
enablement or permanent masks. If temporary inhibitors are needed, undo only those
owned by gaming, preserving pre-existing stopped/masked states.

Provide crash/reboot recovery: a boot must not restart the game or retain a stale
gaming inhibition. Restore only state owned by gaming; do not automatically
reboot, force-kill unrelated processes, or report success after failed restoration.

## 4. Pause active maintenance and competing workloads

Keep the existing Home Assistant maintenance settings and requested-state files;
do not reset helper values or overwrite schedule configuration. No new request,
presence trigger or scheduled maintenance activation is expected during play,
per the user's assumption. Document that limitation instead of promising to
prevent an intentionally excluded scenario.

On entry, use the existing application's pause/maintenance interfaces to stop new
work, then drain active jobs before launching the game. Do not merely call the
shared launcher if its requested state is still true: explicitly invoke the
existing task's inactive behavior through a narrowly scoped lifecycle operation.
Run application actions under the existing service users and authentication
mechanisms; never expose API keys or tokens in command output or committed files.

| Workload | Gaming behavior |
|---|---|
| Tdarr | Pause the node, wait for active files to finish, then keep the node stopped/inactive during play; leave server/UI available where possible |
| Preview generation | Drain current work and stop the container, covering GPU workers as well as CPU workers |
| Ollama | Stop inference service to release VRAM; Open WebUI may remain available but inference is unavailable |
| Immich | Stop ML container and the server process if required to prevent GPU transcoding; photo service downtime is acceptable |
| Plex | Stop during gaming for the initial implementation; this avoids implementing selective transcode restrictions |
| qBittorrent | Apply existing inactive-maintenance seeding behavior, preserving manual stops and ratio/time limits; downloads and VPN can stay running |
| Fan maintenance | End only the maintenance-owned Keep cool override, preserving manual ownership and normal temperature-driven curves |

Determine Tdarr/preview job-drain detection from their actual supported APIs and
current configuration. Do not invent endpoint names or assume process existence
means idle. If an active file cannot drain in a bounded wait, fail session start
with diagnostics and restore prior behavior; do not interrupt destructive media
replacement or force-kill workers. Application pause state changed by gaming must
be recorded so partial startup failure cannot strand work paused.

Keep stopped workload services stopped for the managed session, accounting for
`Restart=` and dependent units/start hooks. Inspect whether associated maintenance
oneshots need temporary suspension to avoid retry loops against stopped apps.
Apply only narrowly scoped coordination; no wholesale maintenance framework
refactor. qBittorrent completion hooks must not resume seeding that gaming stopped;
inspect the existing ownership tracking and add only the minimal session-aware
inactive check needed there if current behavior can resume it without a new
maintenance request. Preserve the VPN namespace and qBittorrent sandbox.

On exit, remove session-owned inhibitors, restart only services previously active,
and reconcile maintenance against the current schedule/request. Do not blindly
resume all workers/seeds or restore an old true/false snapshot after a window has
ended. Use the existing Home Assistant calculation/reconciliation path for current
time without changing user settings; document what happens if HA is unavailable.
Preserve manual Tdarr pauses, torrent stops and fan choices wherever gaming did
not own them. The restore sequence must account for services needing to be ready
before their maintenance API can be called.

Leave SSH, Tailscale, databases, storage, Home Assistant, Forgejo, files and other
unrelated services running. Heavy unrelated jobs are not newly controlled here.
Document resulting service downtime rather than adding CPU-only fallback modes.

## 5. Keep normal cooling and GPU monitoring

The GPU stays on Linux; leave CoolerControl, `coolercontrol-gpu-exhaust`, NVIDIA
telemetry and temperature-driven case-fan curves working throughout gaming.
There is no VFIO cooling workaround and no requirement to force full-speed fans.
Suppress only the maintenance-owned fan-mode override as described above, using
the existing ownership semantics; restore/reconcile it on exit. Check behavior
under sustained CPU/GPU load during the later live session.

## 6. Prepare local yoke and game setup

Inspect the actual USB identity and Linux input devices for the Logitech/Saitek
yoke when available. Confirm axis/button device access for the local logged-in
user and provide narrowly scoped udev permissions only if existing Steam/input
rules are insufficient. Do not grant world-writable input access, use blanket
input-group membership, or pass through a USB controller.

Document separate pedals or USB throttle if present; a throttle attached to the
yoke may enumerate as part of the same device. State device discovery limitations
if hardware is absent. Windows yoke support is not proof of Proton compatibility.

The later runbook should cover Steam edition ownership, user sign-in, dedicated
library selection, Proton selection, Microsoft login, Linux axis/button inspection,
then simulator bindings and calibration. Account for Steam Input remapping as a
possible troubleshooting step if the simulator does not see raw yoke axes.
Start at 1080p/moderate settings and tune only after actual flight measurements.
Do not use the Windows-only `joy.cpl` check as the Linux acceptance criterion.

## 7. Make storage and cleanup predictable

Use an explicit dedicated Steam library on NVMe, for example
`/var/lib/flight-simulator/library`, owned by `jblik`, outside `/scratch`. Document
the actual client/XDG locations as well: Proton prefixes, shader caches, Steam
downloads, game scenery caches, saves, screenshots, Proton builds and logs may
not all live under the game's installation directory. Record canonical paths and
ownership as setup proceeds, including partial installs. Keep shared client data
and other Steam games distinct from this game's removable files.

Provide a simple cleanup command/runbook with a dry-run inventory and these modes:

- Cache cleanup: only identified regeneratable game/download/log caches, with the
  game stopped. Do not classify Proton `compatdata` as disposable cache: it can
  contain saves, settings and authentication data.
- Game removal: uninstall through Steam, then offer explicit removal of residual
  game content, per-game shader data, Proton prefix and user data after showing
  exactly what is lost. Preserve other apps, shared Proton runtimes and Steam login.
- Full feature removal: first stop/recover gaming mode, then remove owned game
  and session files with explicit permission and disable `host.gaming.enable`
  through a later deployment. Keep recovery tools until restoration is complete.

Destructive operations require explicit user authorization, a preview and an
apply/confirmation step. Refuse live processes, unexpected/shared paths and
escaping symlinks; tolerate already-absent files. Do not remove the user's whole
home directory, global Steam state, server media or unrelated downloads. Cloud
sync is not a backup; offer a user-directed export of local saves/bindings before
deleting them without automatically creating backup archives.

There is no allocated VM disk or guest TRIM/compaction step: host files directly
consume NVMe space, and deletion frees actual blocks once no process holds them.
Report `du` allocation and `df -h /` before/after. Shared packages remain subject
to normal Nix generation retention/GC; do not perform global GC or journal cleanup
as a side effect. Retain the initial 200 GiB planning budget and inspect headroom
before later game installation; never automatically delete existing data for room.

## 8. Static verification and documentation

Use the existing flake formatter, evaluate the configuration enabled and disabled,
and build affected outputs/system closure where possible. Linux remote builds may
be required from the Mac; do not activate them. Inspect generated units and
script packaging with existing project/package tools. Add focused checks only
where needed for lifecycle ownership and restoration logic, not a new test framework.

Review failed preparation, repeated stop/recovery, session crash, app drain timeout,
and already-stopped/masked services. Verify maintenance and service code remains
unchanged when gaming is disabled. Document unavailable checks, private-input
access issues and external device/account inputs. Commit verified subtasks locally.

Update README with a brief overview and link to the operator runbook alongside
the implementation. Include local session startup, start/stop/status/recover,
maintenance assumptions, service downtime, library paths, game installation,
yoke setup and cleanup. Do not add dashboard controls, HA gaming automations,
new monitoring infrastructure, CPU pinning or a VM fallback implementation.

## Deferred live acceptance session

Do not execute these during implementation:

1. Deploy in an agreed window; verify normal headless services and SSH still work.
2. Start gaming with active and inactive maintenance requests separately. Verify
   current work drains, Tdarr stays paused, previews/inference/transcoding stop,
   seeding ownership is respected and fan telemetry/curves remain functional.
   No new maintenance activation is expected during either gaming session.
3. Log into the physical display; verify NVIDIA Vulkan, audio, Steam/Microsoft
   login, game installation and a complete flight with working yoke/throttle axes.
4. Verify a torrent completing during gaming does not resume seeding. Confirm
   actual service-start hooks/retries cannot undo the intended workload pause.
5. Exit normally and verify the correct previously active services return, tasks
   follow the current maintenance window, and manual stops/pauses remain respected.
6. Exercise failed start, session crash, repeated recovery and host reboot with
   disposable state; verify no permanent service inhibition or automatic gaming.
7. Observe VRAM/RAM pressure, performance, cooling and NVMe/scratch headroom. Check
   cleanup previews and scoped removal against disposable files only.

Implementation is ready for testing when all configuration, lifecycle and cleanup
artifacts are committed, static checks are reported, and account/device/runtime
inputs are explicit. Successful flights, yoke support and session recovery remain
unproven until this live phase.

## References

- [NixOS Steam configuration](https://wiki.nixos.org/wiki/Steam)
- [Valve Proton](https://github.com/ValveSoftware/Proton)
- [Flight Simulator 2024 Proton compatibility reports](https://github.com/ValveSoftware/Proton/issues/8255)
- [Microsoft Flight Simulator 2024 requirements](https://flightsimulator.zendesk.com/hc/en-us/articles/12702272798364-Microsoft-Flight-Simulator-2024-FAQ)
