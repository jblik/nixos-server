# Homelab Architecture

Two machines on the same LAN, split by **data gravity** vs **compute gravity**.

| | Unraid (existing) | NixOS (this repo) |
|---|---|---|
| Strength | Storage array, many disks, always-on | Fast CPU + single NVIDIA GPU |
| Role | The **store** + low-compute always-on services | **Compute/GPU**: AI, ML offload, VMs |
| Reboots | Rare (it's the storage backbone) | Occasional (GPU handed to VMs) |

The guiding rule: **services live next to the data they need, unless they need the GPU.**
The array lives on unraid, so storage-bound services stay there. GPU-bound work moves
to NixOS, reaching back to unraid data over the network (NFS/SMB) where needed.

---

## What runs where

### Stays on Unraid (storage-bound / low-compute / must-be-up)

These sit next to the array and barely touch the GPU. Moving them buys nothing.

- **Media automation (\*arr):** sonarr, radarr, bazarr, lazylibrarian, jackett,
  flaresolverr, qbittorrent — IO-bound, live next to the downloads/media shares.
- **Requests & curation:** seerr (overseerr), maintainerr.
- **Documents:** paperless-ngx + apache-tika + gotenberg — OCR is light and the docs
  live on the array. (Could later offload OCR to the GPU, but not worth it day one.)
- **Web/util:** microbin, barracudas4-website, redis.
- **Network & ingress (keep where uptime is highest):** pihole (DNS — must stay up
  even when NixOS reboots for a VM), cloudflared tunnel, cloudflareddns.
- **Immich server + PostgreSQL:** the photo library and DB live on the array.
  *Only the ML component is offloaded* (see below).

> **Why pihole/DNS stays on unraid:** the NixOS box reboots whenever the GPU is handed
> to a VM. DNS going down with it would take the whole network offline. Keep critical
> always-on infra on the machine that rarely reboots.

### Moves to / lives on NixOS (GPU/compute)

- **Local AI server** — Ollama (CUDA) + Open WebUI, listening on the LAN so any service
  or device on the network can hit an OpenAI-compatible endpoint (`http://nixos:11434`).
- **Immich machine-learning (CUDA)** — the GPU-heavy half of Immich (face detection,
  CLIP smart-search). Runs here as a container; the Immich **server on unraid** is pointed
  at it via `IMMICH_MACHINE_LEARNING_URL`. This is the headline "offload GPU work from
  unraid" win.
- **Virtualization (libvirt/QEMU/KVM)** with **single-GPU VFIO passthrough** — e.g. a
  SteamOS VM for gaming on the TV. While a VM owns the GPU, the AI/ML services release it.

### Optional later moves (GPU-transcoding candidates)

- **Plex** could move to NixOS for NVENC GPU transcoding, with media mounted from unraid
  over NFS. Trade-off: a network hop to the media and Plex goes down when the GPU is in a
  VM. **Recommendation:** leave Plex on unraid initially; revisit if CPU transcoding hurts.

---

## The single-GPU sharing problem

There is **one** GPU and it can only be used by one consumer at a time. Two consumers
compete for it:

1. **AI/ML services** on the host (Ollama, Immich ML) using the NVIDIA driver + CUDA.
2. **A VM** that needs the *whole* card via PCI passthrough (vfio-pci).

You cannot have the `nvidia` kernel driver and `vfio-pci` bound to the same device at
once. So we switch ownership dynamically:

```
        ┌─────────────── default (host) state ───────────────┐
        │  nvidia driver bound → Ollama + Immich ML use CUDA  │
        └──────────────────────────┬──────────────────────────┘
                                    │  start GPU VM
                                    ▼
   libvirt qemu hook (prepare):  stop ollama + immich-ml
                                 unload nvidia kernel modules
                                 libvirt binds vfio-pci (managed hostdev)
                                    │
                                    ▼
        ┌──────────────── VM owns the GPU ───────────────────┐
        │   full GPU power to SteamOS / gaming VM             │
        └──────────────────────────┬──────────────────────────┘
                                    │  shut down VM
                                    ▼
   libvirt qemu hook (release):  libvirt rebinds nvidia
                                 reload nvidia modules
                                 start ollama + immich-ml again
```

Because the server is **headless** (no desktop on the GPU), this is far simpler than
desktop single-GPU passthrough — there is no display manager / Xorg holding the card.

Requirements wired up in this config:
- **IOMMU** enabled via kernel params (`amd_iommu=on iommu=pt`, switchable to Intel).
- **vfio** modules available; GPU bound to `nvidia` at boot for AI.
- **libvirt qemu hooks** automate the stop→unbind→VM and VM→rebind→start dance
  for the domains listed in `host.gpu.passthroughVms` — just `virsh start
  steamos` / shut the VM down and the GPU is handed over and reclaimed for you.
- A `gpu-status` helper command shows the current driver binding + service state.

> **Cleaner future option:** add a second cheap GPU (or use an AMD iGPU) for the host +
> AI, and dedicate the big NVIDIA card permanently to passthrough. That removes the
> dynamic switching entirely. The config is structured so this is an easy change.

---

## Networking & access

- AI endpoints exposed on the LAN (firewall opens Ollama `11434`, Open WebUI `8080`,
  Immich ML `3003`). Lock these to the LAN subnet / trusted interface.
- DNS continues to be served by pihole on unraid.
- NixOS pulls media/data from unraid over NFS only where a service needs it.

## Config layout (this repo)

```
flake.nix                      # inputs + nixosConfigurations
hosts/nixos-server/            # per-host: hardware-configuration.nix + host.nix
modules/
  options.nix                  # custom `host.*` options (cpu vendor, gpu ids, ports)
  system/                      # boot/iommu, networking, nix, users, ssh, locale
  hardware/                    # nvidia driver + cuda, vfio/passthrough prep
  services/                    # ai (ollama+webui), immich-ml offload
  virtualisation/              # libvirtd, gpu passthrough hooks + scripts
```

Hardware-specific values (GPU PCI IDs, CPU vendor) live in `modules/options.nix` /
the host file and are clearly marked — set them once on the real machine.
