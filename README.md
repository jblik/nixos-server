# nixos-server

NixOS flake for a GPU/compute server that runs alongside an unraid storage box:

- **Local AI server** — Ollama (CUDA) + Open WebUI, on the LAN.
- **GPU ML offload** — Immich machine-learning runs here; the Immich server stays on unraid.
- **VMs with single-GPU passthrough** — e.g. a SteamOS VM for gaming, which takes the
  whole GPU and automatically releases it from the AI services while running.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for what runs on which server and how
the single GPU is shared.

## Layout

```
flake.nix                      inputs + nixosConfigurations."nixos-server"
hosts/nixos-server/
  default.nix                  site knobs (cpu vendor, GPU IDs, LAN subnet, ...)
  hardware-configuration.nix   PLACEHOLDER — regenerate on the real machine
modules/
  options.nix                  custom `host.*` options (the things you change)
  system/                      boot/iommu, networking+firewall, nix, locale, users, ssh
  hardware/                    nvidia driver + cuda toolkit, vfio modules
  services/                    ai (ollama + open-webui), immich-ml offload container
  virtualisation/              libvirtd + automatic GPU passthrough hook
```

Everything site-specific lives in `modules/options.nix` and is set in
`hosts/nixos-server/default.nix`. The rest of the tree is generic.

## First-time install

1. Install a minimal NixOS on the machine (UEFI). Boot into it.
2. Generate the real hardware config and replace the placeholder:
   ```sh
   sudo nixos-generate-config --show-hardware-config \
     > hosts/nixos-server/hardware-configuration.nix
   ```
3. Find the GPU PCI IDs and fill them into `hosts/nixos-server/default.nix`:
   ```sh
   lspci -nn | grep -i nvidia   # -> host.gpu.vendorIds  (GPU + HDMI audio, "10de:XXXX")
   lspci -D  | grep -i nvidia   # -> host.gpu.busIds     ("0000:01:00.0", ".1")
   ```
   Also confirm `host.cpuVendor` (`amd`/`intel`) and tighten `host.lanCidr`.
4. Build & switch:
   ```sh
   sudo nixos-rebuild switch --flake .#nixos-server
   ```
5. Set a real password / drop in your SSH key (see `modules/system/users.nix`).

## Using it

**AI** — from anywhere on the LAN:
```sh
ollama run llama3            # on the server, or:
curl http://<nixos>:11434/api/tags
# OpenAI-compatible base URL: http://<nixos>:11434/v1
```
Open WebUI: `http://<nixos>:8080`.

**Immich ML offload** — on the unraid Immich server set:
```
IMMICH_MACHINE_LEARNING_URL=http://<nixos>:3003
```

**GPU passthrough VM** — create a VM named to match `host.gpu.passthroughVms`
(default `steamos`) in virt-manager, add the GPU + its HDMI-audio function as
PCI host devices (libvirt manages the vfio binding). Then:
```sh
virsh start steamos     # AI services stop, GPU goes to the VM
# ... shut the VM down ...
# AI services come back automatically
gpu-status              # show current driver binding + service state
```

## Notes

- This config is written to pass `nix` evaluation, but **was not built on the target
  hardware** — the `hardware-configuration.nix` placeholder is intentionally
  incomplete so a build fails loudly until you regenerate it (step 2).
- Single GPU = AI and the gaming VM can't run at the same time. To remove that
  trade-off, add a second/iGPU for the host and dedicate the big card to passthrough;
  the module split makes that an easy change.
