# Windows Flight Simulator VM implementation plan

## Objective and execution boundary

Prepare a Windows 11 VM for Microsoft Flight Simulator 2024, using the server's
RTX 3060 and a Logitech G Flight Yoke System connected directly to the server.
NixOS remains the host. GPU-dependent services may be unavailable during gaming.

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
GPU lifecycle handling and operator instructions needed for that later phase.

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
libvirt management local/over SSH; do not expose an unauthenticated listener.
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
  on the NVMe root filesystem, outside `/scratch` and the SATA SSD datasets.
- VirtIO storage and network devices with matching Windows driver installation
  media; a private libvirt NAT network that does not alter `enp5s0`, existing LAN
  addressing, the qBittorrent VPN namespace or production network rules.
- A virtual display for Windows installation and recovery, reachable through an
  SSH tunnel or libvirt remote connection, with no public VNC/SPICE listener.
- Both GPU PCI functions as managed host devices in the gaming configuration.
  Provide an explicit installation configuration without GPU assignment so the
  later Windows installation can happen before the first handoff. These are two
  configurations of the same guest and disk, not two concurrent VMs.

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
Use a directly connected monitor/yoke as the initial path. Include Sunshine on
Windows and Moonlight on the Mac as an optional streaming path, with a display or
documented headless-display requirement. Networking for streaming must be explicit:
for example Tailscale inside Windows to reach a NAT guest, without public port
forwarding. Do not imply Moonlight forwards a flight yoke plugged into the Mac.
USB forwarding from the Mac and VR are outside this implementation.

### 7. Perform static verification and finish the handoff

Use the existing flake formatter, evaluate the host configuration, and build the
affected outputs or system closure where available. Inspect generated domain XML
with the packaged validator and check scripts with tools already provided by the
project/package builders. Verify enabled and disabled module evaluation. Do not
invent a separate testing framework. Building on Linux may be needed because the
editing machine is a Mac; a remote build must not activate the result.

Review generated definitions and hook ordering against the locked libvirt module.
Review all failure paths for service ownership, cooling and driver restoration.
Check that the installation configuration cannot accidentally trigger GPU handoff.
Document commands actually run and limitations, including private flake input or
remote build access failures. Commit implementation subtasks after these checks.

Update README with a short overview and link to an operator runbook alongside the
implementation. Include provisioning, installation/gaming definition selection,
start, graceful shutdown, status, recovery, storage limits and service downtime.
Do not add dashboard controls, Home Assistant gaming automations, backups or new
monitoring infrastructure as part of this task.

## Deferred live acceptance checks

Document these steps for the later testing session; do not execute them now:

1. Build/deploy the configuration in an agreed service window; provision the disk
   and install Windows using the virtual display, then install guest drivers.
2. Confirm the cooling policy and affected service stop sequence before detaching
   the GPU. Keep a separate SSH connection and an operator recovery path available.
3. Start the gaming configuration; verify NVIDIA driver operation, rendering,
   direct display or streaming, and yoke axes/buttons in Windows and the simulator.
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
- [NixOS libvirt guide](https://wiki.nixos.org/wiki/Libvirt)
- [NixOS PCI passthrough guide](https://wiki.nixos.org/wiki/PCI_passthrough)
- [Microsoft Flight Simulator 2024 requirements](https://flightsimulator.zendesk.com/hc/en-us/articles/12702272798364-Microsoft-Flight-Simulator-2024-FAQ)
- [Microsoft peripheral guide, including Logitech Flight Yoke System](https://www.flightsimulator.com/guide/beginners-guide-to-peripherals/)
