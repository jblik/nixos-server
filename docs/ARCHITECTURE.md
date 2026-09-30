# Architecture

**Goal (revised):** collapse the two-machine homelab into **one** NixOS server that
replaces the unraid box entirely — storage array included — while keeping the GPU
workloads (AI, Immich ML, transcoding) it was originally built for.

This document supersedes the earlier two-machine "data gravity vs compute gravity"
split. That design assumed unraid stays; it does not.

---

## 1. The hardware, and what it can honestly do

| | |
|---|---|
| CPU | AMD Ryzen 7 2700X — 8C/16T, Zen+, 3.7 GHz base, 105 W |
| GPU | NVIDIA GeForce RTX 3060 12 GB (GA106, Ampere) |
| RAM | **unknown — must be confirmed** (see open questions) |
| Disks | **unknown — must be inventoried** (see open questions) |

Facts that constrain the design:

- **The 2700X has no integrated GPU.** It is not a G-series APU. There is no fallback
  video engine: if the RTX 3060 is busy or handed to a VM, there is *no* hardware
  transcoding and *no* CUDA on this box at all.
- **NVENC on GA106 does H.264 and HEVC (8/10-bit), but cannot encode AV1.** AV1
  *decode* works. Fine for Plex; relevant if Tdarr targets AV1 (that will be CPU-bound).
- **Consumer NVENC has a concurrent-session cap** (3, raised to 5 on recent drivers;
  removable with the community driver patch). Plex and Tdarr share that budget.
- **12 GB VRAM is a shared budget**, not an LLM budget. Immich ML holds roughly
  1.5–2.5 GB while active, each Plex NVENC stream a few hundred MB. Plan on ~8–9 GB
  actually available to an LLM. This is the single biggest reason to prefer llama.cpp
  over Ollama here — see [AI-BACKEND.md](AI-BACKEND.md).
- **PCIe lanes are tight.** Zen+ gives 16 lanes to the GPU slot, 4 to an M.2, 4 to the
  chipset. A disk HBA goes in the second slot, which on most X470/B450 boards is
  x4 off the chipset. That is ~1.6–2 GB/s — plenty for 8 spinning disks, but it is
  shared with the chipset's SATA/USB.
- **Onboard SATA is usually 6 ports.** An unraid array with more disks than that needs
  an **LSI HBA flashed to IT mode** (9207-8i / 9211-8i / 9300-8i). Budget for one.
- The 2700X is comfortable running ~20 mostly-idle services. It is *not* comfortable
  running Tdarr CPU transcodes, paperless OCR, and a torrent verify at the same time.
  Nice those workloads (`CPUWeight=`, `CPUQuota=` in systemd) rather than hoping.

## 2. What consolidation actually costs

Merging two machines into one is a real trade, not a free win. Stating it plainly:

| Lost | Mitigation adopted here |
|---|---|
| Second machine as an implicit backup copy | **Do not decommission the unraid box.** Repurpose it as the backup target (restic/borg over the LAN). See [MIGRATION.md](MIGRATION.md) phase 7. |
| DNS survives a reboot of the other box | Run a **secondary resolver off-box** (router's own resolver, or a Raspberry Pi) so a `nixos-rebuild` never takes the LAN's DNS with it. |
| Storage services unaffected by GPU work | GPU arbitration (below) — and, preferably, drop the passthrough VM. |
| Blast radius of a bad config | NixOS generations: `nixos-rebuild --rollback`, or pick the previous generation in systemd-boot. This is genuinely better than unraid here. |

## 3. The single-GPU conflict — read this before planning anything else

On the old two-machine design, handing the GPU to a SteamOS VM cost you Ollama and
Immich ML. On the consolidated box, the *same* card is wanted by **four** consumers:

1. LLM inference (llama.cpp / Ollama)
2. Immich machine learning (CUDA)
3. Plex / Tdarr NVENC transcoding
4. A passthrough gaming VM, which demands the **whole card, exclusively**

(1)–(3) coexist fine; they just share VRAM. (4) does not coexist with anything — VFIO
passthrough requires the `nvidia` driver to release the device completely. So starting
the gaming VM now takes down **Plex hardware transcoding and Immich ML on your only
server**, not just a hobby AI endpoint.

**Recommendation: drop the passthrough VM from the consolidated design.** Game on a
different machine, or stream to it. The passthrough modules stay in the tree (they
work) but should be opt-in and off by default.

If the gaming VM is non-negotiable, the honest options are:

- **Accept the outage window.** Extend `host.gpu.hostServices` to stop Plex, Tdarr and
  the LLM backend too, and accept that the media stack degrades to CPU transcoding
  (the 2700X can manage roughly one 1080p stream, not 4K) while you play.
- **Add a second GPU.** A cheap card (or a Quadro P400-class) for host/NVENC duty,
  with the 3060 dedicated permanently to passthrough. This removes the dynamic
  bind/unbind dance entirely and is the clean answer. Costs a PCIe slot — which is the
  same slot the HBA wants. Check the board before committing.

> **Correction to the previous doc:** it claimed "the NixOS box reboots whenever the GPU
> is handed to a VM". It does not. The qemu hook stops services and unloads the nvidia
> modules; no reboot is involved. The old justification for keeping pihole elsewhere was
> therefore wrong — the real reason is rebuild/reboot cadence, which is addressed with a
> secondary resolver instead.

## 4. Storage

The array is the part unraid was actually doing, and the part this repo currently has
**zero** configuration for. It is designed in [STORAGE.md](STORAGE.md). Summary:

- **Fast tier** — ZFS mirror on 2× SSD/NVMe: service state, PostgreSQL, Redis, VM
  images, GGUF models, transcode scratch. Snapshots + replication.
- **Bulk tier** — per-disk XFS HDDs unioned by **mergerfs**, parity-protected by
  **SnapRAID**. This is the closest true analogue to unraid: mixed disk sizes, disks
  spin down independently, add a disk whenever, and a failure beyond parity loses only
  that disk's files rather than the pool.

The choice of SnapRAID also unlocks a migration shortcut: unraid data disks are plain
single-disk XFS filesystems with no striping, so **they can be mounted directly on
NixOS and adopted into the new pool without copying the data**. Only parity is rebuilt.

## 5. Service placement

Everything runs here now. The rule becomes: **use a native NixOS module when one
exists; fall back to an OCI container only when it doesn't.** Native modules give
declarative config, real systemd hardening, and no image-tag drift.

Verified against the pinned nixpkgs (`nixos-26.05`):

| Current container | Target on NixOS |
|---|---|
| paperless-ngx + apache/tika + gotenberg | `services.paperless` with `configureTika = true` — **one option replaces all three containers** |
| immich (server, on unraid) + immich-ml | `services.immich` — server, ML, Postgres and Redis in one module. The separate ML-offload container in this repo becomes redundant. |
| plex | `services.plex` |
| sonarr / radarr / bazarr / jackett | `services.sonarr` / `radarr` / `bazarr` / `jackett` |
| qbittorrent | `services.qbittorrent` (declarative `serverConfig`) |
| seerr (overseerr) | `services.overseerr` |
| lazylibrarian | `services.readarr` (native) if you're willing to switch; otherwise container |
| flaresolverr | `services.flaresolverr` |
| microbin | `services.microbin` |
| redis | `services.redis.servers` |
| cloudflared / cloudflareddns | `services.cloudflared` / container for DDNS |
| pihole | **no NixOS module.** Either run it as a container, or switch to `services.blocky` / `services.adguardhome` (both native, both declarative). |
| tdarr | container (no module) |
| maintainerr | container (no module) |
| jblik/laundry-notifier, jblik/barracudas4-website | containers — your own images, keep them |
| ollama + open-webui | `services.llama-swap` + `services.llama-cpp`, or keep `services.ollama` — see [AI-BACKEND.md](AI-BACKEND.md) |

Also worth adding while you're here, all native: `services.smartd` + `services.scrutiny`
(disk health — you lose unraid's dashboard, replace it), `services.restic` /
`borgbackup`, `services.sanoid` + `syncoid` (ZFS snapshots/replication),
`services.homepage-dashboard` (service index), `services.tailscale`, and
`services.authelia` if anything gets exposed.

## 6. Config layout

```
flake.nix                      inputs + nixosConfigurations
hosts/nixos-server/            hardware-configuration.nix + site knobs
modules/
  options.nix                  custom `host.*` options — everything site-specific
  system/                      boot/iommu, networking, nix, users, ssh, locale
  hardware/                    nvidia driver + cuda, vfio prep
  storage/                     ZFS fast pool, mergerfs bulk pool, snapraid parity
  services/                    ai backend, media, documents, photos, network
  virtualisation/              libvirtd + opt-in GPU passthrough hooks
```

## 7. Known defects in the current tree

Found while reviewing; each is tracked as a task in [MIGRATION.md](MIGRATION.md).

1. **`host.gpu.vendorIds` and `host.gpu.busIds` are dead options.** They are declared,
   documented, and the README instructs you to fill them in — but no module reads
   them. Either wire them into a vfio/rebind script or delete them.
2. **`hardware.nvidia.modesetting.enable = true` on a headless box works against the
   passthrough hook.** It loads `nvidia_drm` with modeset, which routinely pins the
   module and makes the hook's `modprobe -r` fail. The hook swallows that with
   `|| true`, so libvirt then fails to bind vfio-pci and the VM starts *without* the
   GPU — silently. Set `modesetting.enable = false` for headless, and make the hook
   fail loudly instead of `|| true`.
3. **No storage configuration at all.** `hardware-configuration.nix` is still the
   placeholder. Nothing defines filesystems, the array, or mounts.
4. **No secrets management.** `initialPassword = "changeme"`, and the consolidated
   server will hold a Cloudflare tunnel token, *arr API keys, and Immich DB
   credentials. Needs `sops-nix` or `agenix` before anything real lands.
5. **No backups, no monitoring, no reverse proxy** — all three were implicitly
   somebody else's job under the two-machine design.
6. **`services.xserver.videoDrivers = [ "nvidia" ]`** on a headless server is the
   supported way to load the driver, but deserves a comment saying so; it reads like
   a mistake.
7. **`firewall.extraInputRules`** builds an nftables set from a port list; if that list
   is ever empty it emits `{ }` and the ruleset fails to load. Guard it.

## 8. Open questions — these block real numbers

The plan is written to be correct without them, but these must be answered before
buying anything or formatting a disk:

1. **Disk inventory** — how many drives, what sizes, current unraid parity layout, and
   how full is the array today?
2. **Motherboard model and free PCIe slots** — decides HBA vs onboard SATA, and whether
   a second GPU is even possible.
3. **RAM installed** — ZFS ARC plus ~20 services plus llama.cpp host-side buffers.
   32 GB is the floor; 64 GB is the comfortable answer.
4. **PSU wattage and drive bays/cooling** — 105 W CPU + 170 W GPU + N spinning disks.
5. **Is the gaming VM staying?** This is the fork in the road for section 3.
6. **Is the unraid box being kept as a backup target?** Strongly recommended.
