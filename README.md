# nixos-server

NixOS flake for a single server that is intended to **replace an existing unraid box
entirely** — array included — while also doing the GPU work it was built for.

- **Storage array** — mergerfs union over per-disk XFS, parity by SnapRAID, plus a
  ZFS mirror for databases and other hot state. The unraid replacement.
- **Local AI server** — CUDA llama.cpp behind llama-swap (or Ollama), OpenAI-compatible
  on the LAN, with Open WebUI.
- **Everything else that was on unraid** — media stack, Immich, paperless, DNS, and the
  rest, mostly as native NixOS modules rather than containers.
- **VMs with single-GPU passthrough** — supported, but read the warning below first.

**Start here:**

| Doc | What it answers |
|---|---|
| [docs/MIGRATION.md](docs/MIGRATION.md) | **The master plan.** Nine phases from disk inventory to retiring unraid, with exit gates, a risk register, and effort estimates. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | What the hardware can actually do, what consolidation costs, where each service lands. |
| [docs/STORAGE.md](docs/STORAGE.md) | The array: why mergerfs + SnapRAID over ZFS/btrfs/mdadm, and how to migrate without copying data. |
| [docs/AI-BACKEND.md](docs/AI-BACKEND.md) | Ollama vs llama.cpp, and why the shared GPU decides it. |

> **Before you plan anything around the gaming VM:** on a consolidated server, handing
> the GPU to a passthrough VM also takes down Plex hardware transcoding and Immich ML,
> because there is no second machine and the 2700X has no iGPU. ARCHITECTURE §3 covers
> the options. The recommendation is to drop the passthrough VM.

## Layout

```
flake.nix                      inputs + nixosConfigurations."nixos-server"
hosts/nixos-server/
  default.nix                  site knobs (GPU IDs, disks, subnet, AI models, ...)
  hardware-configuration.nix   PLACEHOLDER — regenerate on the real machine
modules/
  options.nix                  custom `host.*` options (the things you change)
  system/                      boot/iommu, networking+firewall, nix, locale, users, ssh
  hardware/                    nvidia driver + cuda toolkit, vfio modules
  storage/                     zfs fast pool, mergerfs union, snapraid parity, spin-down
  services/                    ai backend (llama-swap | ollama) + open-webui, immich-ml
  virtualisation/              libvirtd + automatic GPU passthrough hook
```

Everything site-specific lives in `modules/options.nix` and is set in
`hosts/nixos-server/default.nix`. The rest of the tree is generic. Modules stay inert
until their knobs are filled in — an empty `host.storage.dataDisks` simply disables the
bulk tier.

## First-time install

1. Install a minimal NixOS on the machine (UEFI). Boot into it.
2. Generate the real hardware config and replace the placeholder:
   ```sh
   sudo nixos-generate-config --show-hardware-config \
     > hosts/nixos-server/hardware-configuration.nix
   ```
3. Fill in `hosts/nixos-server/default.nix`. Each block says which command produces
   its values:
   ```sh
   lspci -nn | grep -i nvidia                          # -> host.gpu.vendorIds
   lspci -D  | grep -i nvidia                          # -> host.gpu.busIds
   lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINT   # -> host.storage.dataDisks
   head -c 8 /etc/machine-id                           # -> host.storage.hostId
   ```
   Also confirm `host.cpuVendor` (`amd`/`intel`) and tighten `host.lanCidr`.
4. **Add the CUDA binary cache before the first build**, or `llama-cpp`/`ollama-cuda`
   compile locally and that takes hours on a 2700X — see
   [docs/AI-BACKEND.md](docs/AI-BACKEND.md) §6.
5. Build & switch:
   ```sh
   sudo nixos-rebuild switch --flake .#nixos-server
   ```
6. Set a real password / drop in your SSH key (see `modules/system/users.nix`).

Do **not** point `host.storage.dataDisks` at disks that still hold the only copy of
your data. Follow [docs/MIGRATION.md](docs/MIGRATION.md) phases 3–4 instead.

## Using it

**AI** — from anywhere on the LAN:
```sh
curl http://<nixos>:11434/v1/models
# OpenAI-compatible base URL: http://<nixos>:11434/v1
```
Open WebUI: `http://<nixos>:8080`. Both backends serve the same API on the same port,
so switching `host.ai.backend` changes nothing for clients.

With the default `llama-swap` backend, drop GGUF files into `/var/lib/models` and
declare them in `host.ai.models`; llama-swap starts a `llama-server` per model on
demand and unloads it after its TTL, handing the VRAM back to Immich ML and Plex.

**Storage** — the union is at `/mnt/storage`; the individual disks stay at `/mnt/diskN`:
```sh
snapraid status        # array state, last sync, unscrubbed blocks
snapraid sync          # normally on a timer (host.storage.syncInterval)
hdparm -C /dev/sdX     # is that disk spun down?
```

**Immich ML offload** — only relevant until Immich itself moves here (MIGRATION phase
5, wave 4). Until then, on the unraid Immich server:
```
IMMICH_MACHINE_LEARNING_URL=http://<nixos>:3003
```

**GPU passthrough VM** — create a VM named to match `host.gpu.passthroughVms`
(default `steamos`) in virt-manager, add the GPU + its HDMI-audio function as
PCI host devices (libvirt manages the vfio binding). Then:
```sh
virsh start steamos     # GPU-holding services stop, GPU goes to the VM
# ... shut the VM down ...
# they come back automatically
gpu-status              # show current driver binding + service state
```

## Notes

- This config is written to pass `nix` evaluation, but **was not built on the target
  hardware** — the `hardware-configuration.nix` placeholder is intentionally
  incomplete so a build fails loudly until you regenerate it (step 2).
- Known defects in the current tree are listed in
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §7 and scheduled as phase 1 of the
  migration.
- `nix fmt` formats the tree with `nixfmt-tree`, on Linux and macOS.
