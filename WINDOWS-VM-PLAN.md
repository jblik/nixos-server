# Windows Flight Simulator VM implementation plan

## Objective and execution boundary

Prepare a Windows 11 VM for Microsoft Flight Simulator 2024, using the server's
RTX 3060 and a Logitech G Flight Yoke System connected directly to the server.
NixOS remains the host. GPU-dependent services may be unavailable during gaming.
Use a monitor connected directly to the RTX 3060 by HDMI or DisplayPort for both
Windows installation and gaming. This avoids video streaming, encoding/decoding
and network latency; CPU and device virtualization overhead still remains.
Remote guest display, streaming and remote guest control are outside scope.
Keep existing SSH access for NixOS administration and recovery.

Implement the repository changes autonomously, following the working agreement.
Keep changes local and commit completed, verified subtasks with `jj commit` and
one-line conventional commit messages. Never push or rewrite existing changes.
This document is a plan, not an instruction to deploy the implementation now.

Live testing is a separate, later phase. Do not switch the running NixOS system,
reboot, stop production services, bind/unbind hardware, start the VM, or install
Windows during implementation. Formatting, evaluation and build checks are still
required before committing code, using the existing tools. Record anything that
cannot be checked; do not claim GPU handoff works before the later live tests.

The completed implementation must provide the configuration, provisioning commands,
GPU lifecycle handling, cleanup commands and operator instructions needed for that
later phase. Cleanup is implemented now but executed only on an explicit later
request; this plan does not authorize deleting files.

## Observed hardware and storage

Read-only SSH inspection during planning found the following. Recheck before any
later deployment; these are observations, not permanent device discovery rules.

| Item | Observation |
|---|---|
| CPU | Ryzen 7 2700X, 8 cores / 16 threads |
| Memory | 48 GB reported in the repository README |
| GPU | RTX 3060, `0000:09:00.0`, PCI ID `10de:2503` |
| GPU audio | `0000:09:00.1`, PCI ID `10de:228e` |
| Isolation | IOMMU group 22 contains only those two functions |
| Current drivers | Graphics: `nvidia`; audio: `snd_hda_intel` |
| NVMe | ADATA SX8200NP, 447.1 GiB physical capacity |
| NVMe root filesystem | 321 GiB available, shared with `/scratch` and NixOS |
| SATA SSD mirror `fast` | 139 GiB available for existing services |
| HDD union `/data` | Approximately 8.2 TiB available |

IOMMU is already active on the inspected boot. Do not add speculative boot flags,
ACS overrides, permanent GPU blacklists or boot-time VFIO ownership. Linux should
own the RTX 3060 during normal server operation. The 2700X has no integrated GPU;
SSH must remain usable when Windows owns the only graphics card.

## Implementation sequence

### 1. Inspect the pinned interfaces and existing patterns

Read `flake.nix`, `modules/options.nix`, `modules/system/default.nix`,
`modules/system/users.nix`, `modules/hardware/nvidia.nix`, and the affected service
and fan modules before editing. Inspect the libvirt/QEMU NixOS modules from the
locked nixpkgs revision for exact options, service names, hooks, firmware paths
and permissions. Do not copy outdated NixOS examples or update flake inputs.

Inspect the evaluated configuration for all units that can open NVIDIA devices,
including generated container units and monitoring. Read the maintenance scripts
and fan scripts, rather than inferring their behavior from unit names.
Read-only discovery over SSH is allowed; no remote changes are needed yet.

### 2. Add the VM host configuration

Follow the current `host.*` option and module layout. Use a small dedicated module,
such as `modules/system/gaming-vm/default.nix`, imported by the system module, with
scripts/templates alongside it. Add only the enable switch and host-specific
values actually required; avoid a generic VM framework or a new flake dependency.
Enable the configuration for this host in the checked-in configuration, but do
not deploy it as part of implementation.

Enable KVM/libvirt, supported UEFI firmware, Secure Boot capability and software
TPM 2.0 for Windows 11. Use the pinned packages' supported configuration. Keep
libvirt management on the server's local socket; administer it with commands run
on the server over existing SSH. Do not add remote libvirt listeners or clients.
Grant `jblik` only the access required for normal VM management, following the
existing password-protected sudo policy. Do not enable VM autostart.

### 3. Define the guest and persistent storage

Use one guest named `windows-flight-sim` with these initial settings:

- 32 GiB RAM and 12 vCPUs, presented as 1 socket, 6 cores, 2 threads, using a
  host-compatible CPU model. This does not reserve physical cores; defer pinning,
  hugepages and performance tuning until measurements justify them.
- Q35 machine type, UEFI, persistent writable NVRAM and persistent software TPM
  state. Do not regenerate these on rebuild or routine provisioning.
- One 200 GiB virtual disk under `/var/lib/libvirt/images/windows-flight-sim/`
  on the NVMe root filesystem, outside `/scratch` and the SATA SSD datasets. Use
  sparse qcow2 storage with supported guest discard/unmap for space reclamation.
- VirtIO storage and network devices with matching Windows driver installation
  media; a private libvirt NAT network that does not alter `enp5s0`, existing LAN
  addressing, the qBittorrent VPN namespace or production network rules.
- Both GPU PCI functions as managed host devices, with the RTX 3060 as the guest's
  display from the first Windows installer boot. Do not add an emulated graphics
  adapter, SPICE/VNC server or remote display tunnel. Firmware/installer output
  on the physical monitor must be checked during the later live session; document
  blank-screen recovery through host SSH without assuming guest display access.
- Explicit USB passthrough for a keyboard and mouse connected to the server so
  Windows setup is usable before the yoke is configured. Discover their actual
  identities like the yoke; do not assign a whole USB controller or all HID
  devices. Preserve any input devices needed for host recovery.

Keep the domain definition reproducible from tracked templates/Nix output.
Provide an explicit, idempotent provisioning command that creates missing disk
and guest state, validates existing state and defines the domain without starting
it. Refuse to replace existing disks, reset TPM/NVRAM, or redefine a running guest.
Do not run provisioning during NixOS activation. Use correct QEMU ownership and
permissions, derived from the pinned configuration.

A sparse disk may consume less initially, but budget the full 200 GiB: that leaves
roughly 121 GiB at the observed usage for host growth and scratch work. Document
that this is shared capacity, not a reservation. Check free space before later
provisioning; do not automatically delete downloads or Nix generations to make room.

Windows media must come from Microsoft and VirtIO drivers from the official
virtio-win distribution. Document local ISO paths and acquisition steps. If media
is unavailable, finish all implementation with clearly documented runtime inputs;
do not invent credentials, redistribute Windows media, bypass Windows requirements
or embed license keys. Microsoft sign-in, activation and game purchase/installation
are later interactive steps. Do not automate purchases or account creation.

### 4. Implement coordinated GPU handoff and recovery

Use the pinned libvirt hook interface, scoped strictly to `windows-flight-sim` and
only when its definition assigns this GPU. Cover starts initiated through libvirt
as well as any convenience commands. Use a lock to serialize transitions and
explicit state recording to track the phase and the services changed.

Before GPU assignment:

- Revalidate the two PCI devices and their actual IOMMU group membership. Do not
  rely on group number 22 remaining constant. Abort if unrelated devices appear.
- Record active affected units and prevent their restart during GPU ownership,
  including restarts requested by maintenance schedules or dependencies.
- Stop GPU workloads cleanly: Ollama, Plex, the Tdarr node, preview generation,
  Immich ML, and any Immich server process capable of GPU video transcoding.
  Prefer temporarily stopping the Immich server over adding a new CPU-only mode
  just to preserve browsing. This means Immich may be unavailable during gaming.
- Include NVIDIA persistence/monitoring processes and CoolerControl's GPU access
  where present. Do not stop databases, storage, SSH, Tailscale, Home Assistant or
  unrelated services. Stop the Tdarr server only if inspection proves necessary.
- Check for remaining device users. Fail with useful diagnostics rather than
  killing arbitrary processes, forcing module removal or detaching busy devices.
- Release host NVIDIA resources in the required order and let libvirt manage
  PCI driver assignment. Avoid conflicting manual and managed detach operations.

After guest resource release, restore the Linux drivers and only the units that
this transition stopped. Restore temporary restart inhibitors, cooling settings
and maintenance behavior. Ensure NVIDIA container device mappings remain valid
after reattachment; regenerate them through existing mechanisms if needed.

Handle partial preparation failure and failed VM startup with cleanup. Make
repeated cleanup safe. Do not call `virsh`/libvirt APIs synchronously from libvirt
hooks, which can deadlock; any follow-up libvirt operations must happen outside
the hook. Use bounded operations and log each transition to the journal.

Provide status and explicit recovery commands for interrupted transitions. If
restoration fails, report it and retain enough state to recover; do not silently
restart GPU consumers against a broken device or automatically reboot the server.
Runtime inhibitors must not become permanent masks across boots. Explain how
recovery handles stale state after a host reboot or libvirt daemon restart.

### 5. Keep cooling functional while GPU telemetry is absent

The existing fan configuration uses GPU temperature in case-fan curves, and
`coolercontrol-gpu-exhaust` reads GPU telemetry through CoolerControl. Merely
stopping this helper or unloading NVIDIA may leave stale readings or inadequate
case airflow.

Implement a temporary gaming cooling policy before releasing the GPU. Reuse the
existing full-speed mode if supported, ensure the hardware retains adequate fan
speeds if CoolerControl must stop to release NVIDIA, and prevent maintenance from
overriding the policy during gaming. Inspect the CoolerControl behavior/API before
choosing the exact sequence. Do not assume its GPU backend can be disabled at
runtime. If necessary, use the existing motherboard PWM controls after releasing
CoolerControl ownership. Keep these changes scoped to GPU ownership.

Restore the prior fan mode and reconcile the current maintenance request after
reattachment. Live verification of airflow and temperatures is deferred, but a
concrete cooling implementation is required before the handoff is ready to test.

### 6. Prepare yoke passthrough and guest setup instructions

Discover the actual yoke USB vendor/product IDs read-only if it is plugged into
the server. Do not guess IDs or pass through a whole USB controller. Provide the
guest USB host-device entry and a documented way to supply IDs later if absent.
The guest should remain installable without a connected yoke; normal yoke support
must not be silently treated as complete until device identity is supplied.

Document any additional USB devices, such as separate pedals or a USB throttle,
individually. A throttle attached through the yoke may not enumerate separately.

Write the later guest installation runbook: Windows setup, VirtIO drivers, NVIDIA
driver, Windows updates, Flight Simulator, then `joy.cpl` and simulator bindings.
Use the directly connected monitor, keyboard, mouse and yoke throughout. Do not
install Sunshine, Moonlight, guest Tailscale, RDP or other remote-access services,
or add streaming ports, port forwards, virtual displays or headless-display
drivers. Keep guest NAT networking for Windows updates, sign-in and simulator
content. USB forwarding from the Mac and VR are outside this implementation.

### 7. Perform static verification and finish the handoff

Use the existing flake formatter, evaluate the host configuration, and build the
affected outputs or system closure where available. Inspect generated domain XML
with the packaged validator and check scripts with tools already provided by the
project/package builders. Verify enabled and disabled module evaluation. Do not
invent a separate testing framework. Building on Linux may be needed because the
editing machine is a Mac; a remote build must not activate the result.

Review generated definitions and hook ordering against the locked libvirt module.
Review all failure paths for service ownership, cooling and driver restoration.
Check that all guest starts, including Windows installation, use the same GPU
handoff and recovery sequence, and that no remote guest listeners are introduced.
Document commands actually run and limitations, including private flake input or
remote build access failures. Commit implementation subtasks after these checks.

Update README with a short overview and link to an operator runbook alongside the
implementation. Include provisioning, installer-media attachment and detachment,
start, graceful shutdown, status, recovery, storage limits and service downtime.
Do not add dashboard controls, Home Assistant gaming automations, backups or new
monitoring infrastructure as part of this task.

## Cleanup and space reclamation plan

Implement cleanup alongside provisioning, so removing this experiment does not
require reconstructing where files were written. The command names below describe
the intended interface; they do not exist until the implementing agent adds them.
Keep the implementation small and scoped to this guest.

### Track owned files from the beginning

Use one dedicated download directory, `/var/cache/windows-flight-sim/`, for newly
downloaded Windows/VirtIO ISOs, standalone driver installers, partial downloads
and temporary extraction files. Keep downloads out of the Nix store and unrelated
service caches. Game downloads inside Windows live inside its virtual disk.

Provisioning must record a root-owned inventory of the guest name/UUID, created
disk paths, download paths, NVRAM, TPM state and any private network it creates.
Update it as resources are created, so cleanup also works after partial setup.
Record external inputs separately: an ISO supplied from elsewhere is not owned
by this VM and must not be deleted automatically. Document installer copies made
on the Mac and their exact locations for separate manual removal.

Do not create snapshots, backing chains, copied VM disks or backup archives as an
incidental provisioning step. If such artifacts are introduced later, record them
explicitly because they can retain allocated storage after the main disk is gone.

### Provide three explicit cleanup operations

| Intended operation | Removes | Preserves |
|---|---|---|
| `gaming-vm cleanup-downloads` | Owned ISOs, installers, partial downloads and extraction files | Windows disk, guest definition, NVRAM and TPM state |
| `gaming-vm reclaim-space` | No host files; reports guest TRIM instructions and host allocation | Windows, game and saved data |
| `gaming-vm remove` | This guest's disk, downloaded files, definition and owned persistent/runtime state | All unrelated services, VMs, media and storage |

Cleanup defaults to a dry-run inventory with canonical paths and actual allocated
sizes. Require an explicit apply flag for downloaded-file deletion and an explicit
guest-specific destructive confirmation for full removal. An agent must obtain
the user's permission before destructive execution under the working agreement.
Refuse unexpected paths, symlinks escaping owned directories, shared resources and
ambiguous ownership. Repeated cleanup must tolerate already-absent owned files.

For download-only cleanup, refuse files attached to any running guest. Once
Windows is installed, document how to detach installation media from the inactive
definition before deleting it. Preserve externally supplied or shared ISOs.

For reclaiming space while keeping Windows, document uninstalling unwanted game
content and clearing caches through Windows/the simulator, followed by Windows
Optimize Drives/ReTrim with discard enabled on the VM disk. Deleting guest files
alone may not reduce the host file's allocation. Do not shrink partitions or run
`qemu-img` modification/conversion against an active disk. Offline compaction is
an optional separately planned recovery step if TRIM fails, not the default path.

### Full removal order

1. Print the owned-resource inventory and warn that Windows, the installed game,
   local saves, settings and guest credentials will be lost. Any requested export
   happens before removal; do not assume cloud sync is a backup.
2. Shut Windows down gracefully through the existing lifecycle path. Refuse
   removal while it is running, paused, or GPU recovery is incomplete; do not
   force-kill it as a side effect of cleanup.
3. Restore GPU drivers, cooling, affected services and maintenance behavior. Keep
   hooks and recovery helpers installed until this is complete.
4. Capture the inactive domain's actual storage/NVRAM/TPM paths before undefining
   it. Remove its definition and owned NVRAM, TPM, managed-save and snapshot state
   using the pinned libvirt version's supported interfaces. Removing snapshot
   metadata alone does not remove external disk images. Avoid indiscriminate
   `--remove-all-storage`, which could include supplied/shared media.
5. Delete only inventoried owned disk files and downloads, then owned handoff
   state, temporary inhibitors and per-guest logs. Verify no process still holds
   deleted VM files open. Remove a private network only if created exclusively
   for this guest and unused; preserve shared libvirt networks and storage pools.
6. Document disabling `host`'s gaming VM option and deploying that change after
   data cleanup. This must not recreate the domain/disk or change normal NVIDIA
   service configuration. Removing packages/configuration alone does not remove
   VM data; retain the cleanup tools until data removal is complete.
7. Report `df -h /` before/after and `du` allocated sizes for surviving owned
   directories. Check for leftover images, downloads, snapshots and managed-save
   files. Report each item that could not be removed rather than claiming success.

The 200 GiB disk capacity is a logical maximum, not necessarily 200 GiB of host
allocation. Full deletion returns its actual allocated blocks; guest RAM is
released on shutdown. Routine global Nix garbage collection, old generation
removal and global journal vacuuming are outside this cleanup because they affect
other workloads. Note that shared packages may remain in the Nix store until the
operator's normal generation-retention and garbage-collection policy releases them.

Add cleanup commands, ownership locations and expected space accounting to the
operator runbook. Verify cleanup statically during implementation; dry-run,
download-only deletion, TRIM and full teardown of disposable test data belong to
the later live acceptance session. Never exercise full removal against the user's
installed VM merely to verify the cleanup implementation.

## Deferred live acceptance checks

Document these steps for the later testing session; do not execute them now:

1. Build/deploy the configuration in an agreed service window; provision the disk
   and connect the monitor to the RTX 3060, plus the passed-through USB inputs.
2. Confirm the cooling policy and affected service stop sequence before detaching
   the GPU. Keep a separate SSH connection and an operator recovery path available.
   Start the Windows installer on the physical display, install Windows and guest
   drivers, then detach installer media from the inactive guest definition.
3. Verify NVIDIA driver operation, rendering on the directly connected monitor,
   and yoke axes/buttons in Windows and the simulator.
4. Shut down Windows normally; verify Linux driver ownership, NVIDIA container
   access, an Ollama request, GPU transcoding and restored fan/maintenance behavior.
5. Repeat several complete cycles without rebooting the host. Separately exercise
   failed startup and forced VM termination after the normal path is proven.
6. Observe CPU/RAM pressure, temperatures, disk growth and scratch headroom during
   actual flight. Decide on tuning from those results.

The implementation handoff is complete when configuration and scripts are
committed, static checks are reported, and the remaining media/account/device
inputs and live checks are explicit. Runtime passthrough reliability remains
unproven until the later session; needing a reboot is a possible outcome, not an
implementation success to assume away.

## Reference documentation

- [Libvirt domain XML](https://libvirt.org/formatdomain.html)
- [Libvirt hooks and API deadlock restrictions](https://libvirt.org/hooks.html)
- [Libvirt removal flags and storage limitations](https://www.libvirt.org/manpages/virsh.html)
- [QEMU discard/unmap behavior](https://www.qemu.org/docs/master/system/qemu-manpage.html)
- [NixOS libvirt guide](https://wiki.nixos.org/wiki/Libvirt)
- [NixOS PCI passthrough guide](https://wiki.nixos.org/wiki/PCI_passthrough)
- [Microsoft Flight Simulator 2024 requirements](https://flightsimulator.zendesk.com/hc/en-us/articles/12702272798364-Microsoft-Flight-Simulator-2024-FAQ)
- [Microsoft peripheral guide, including Logitech Flight Yoke System](https://www.flightsimulator.com/guide/beginners-guide-to-peripherals/)
