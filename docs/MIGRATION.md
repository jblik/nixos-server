# Master plan — replacing the unraid server

**Objective:** one NixOS machine runs everything the unraid box ran, plus the GPU
workloads, with the array intact and no data loss.

**Feasibility: yes, with two caveats.** The service side is genuinely easy — most of
your containers have native NixOS modules and the machine is fast enough. The two hard
parts are (a) the storage array, which this repo has no configuration for at all, and
(b) the single GPU, which now has four consumers instead of two. Both are solved in
[STORAGE.md](STORAGE.md) and [ARCHITECTURE.md](ARCHITECTURE.md) §3.

**Governing rules for the whole migration:**

1. **Never let data exist in only one place.** The old array stays valid and bootable
   until the new one is synced, scrubbed, and verified.
2. **One wave at a time.** Migrate a group of services, run it for a few days, then
   move on. Do not flip twenty services in a weekend.
3. **DNS goes last.** It is the thing that makes every other failure look like a
   network outage.
4. **Every phase has an exit gate.** If the gate does not pass, do not start the next
   phase.
5. **Commit each phase.** The repo is the rollback mechanism; `nixos-rebuild
   --rollback` only helps if the config that worked is in git.

---

## Phase 0 — Inventory and decisions

Nothing is buildable until these are known. Run on the unraid box and the new machine.

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINT   # disk inventory, both machines
blkid                                               # confirm every data disk is XFS
df -h /mnt/disk*                                    # how full is the array
free -g                                             # RAM on the new box
lspci -nn                                           # GPU IDs, free slots, existing HBA
lspci -nn | grep -i nvidia                          # -> host.gpu.vendorIds
lspci -D  | grep -i nvidia                          # -> host.gpu.busIds
sudo dmidecode -t baseboard                         # motherboard model -> SATA/PCIe budget
```

Decisions to make now, because they change what gets built:

| Decision | Recommendation |
|---|---|
| Keep the GPU passthrough gaming VM? | **No.** It takes down Plex transcoding and Immich ML on your only server. See ARCHITECTURE §3. |
| Array technology | mergerfs + SnapRAID bulk tier, ZFS mirror fast tier (STORAGE §2) |
| Keep the unraid hardware? | **Yes — as the backup target.** Do not sell it. |
| pihole, or switch DNS? | Either. `services.blocky` / `adguardhome` are native and declarative; pihole means a container. |
| AI backend | Start with whatever works, end on `llama-swap` (AI-BACKEND §5) |
| Secrets | `sops-nix` (recommended) or `agenix`. Required before real credentials land. |

**Gate:** disk inventory written down, enough SATA ports (or an HBA ordered), RAM
confirmed ≥ 32 GB, and the gaming-VM question answered.

---

## Phase 1 — Fix the defects in the current tree

Cheap, and they will bite later. Each is described in ARCHITECTURE §7.

- [ ] Wire `host.gpu.vendorIds` / `busIds` into something real, or delete them — right
      now the README tells you to fill in options nothing reads.
- [ ] `hardware.nvidia.modesetting.enable = false` for headless, so the passthrough
      hook's `modprobe -r nvidia` can actually succeed.
- [ ] Make the qemu hook **fail loudly** instead of `|| true`, so a VM never silently
      boots without its GPU.
- [ ] Guard the firewall rule against an empty port list.
- [ ] Add the CUDA binary cache (AI-BACKEND §6) *before* the first CUDA rebuild.
- [ ] Add `sops-nix` and move `initialPassword` to a real hashed secret.

**Gate:** `nix flake check` passes and the tree has no options that do nothing.

---

## Phase 2 — Bring up the real hardware

Base OS only. No data, no services.

1. Install minimal NixOS (UEFI), boot it.
2. `sudo nixos-generate-config --show-hardware-config > hosts/nixos-server/hardware-configuration.nix`
   — replaces the placeholder that currently blocks any real build.
3. Fill in the site knobs in `hosts/nixos-server/default.nix`: GPU IDs, real
   `lanCidr` (tighten it from `192.168.0.0/16`), SSH key.
4. Turn on the things unraid did for you invisibly: `services.smartd`,
   `services.scrutiny`, `services.tailscale` for out-of-band access.
5. Verify the GPU: `nvidia-smi`, `nvtop`.

**Gate:** reboots cleanly, reachable over SSH and Tailscale, `nvidia-smi` sees the
3060, SMART reports on every attached disk.

---

## Phase 3 — Build the array

The one-way door. Move slowly.

1. **Fast tier first** — 2× SSD as a ZFS mirror. Datasets for service state, Postgres
   (`recordsize=16k`), models, VM images, transcode scratch.
2. **Bulk tier, empty** — attach any *spare* disks, XFS each, mount at `/mnt/diskN`,
   union with mergerfs to `/mnt/storage`, configure `services.snapraid`.
3. **Rehearse a restore on the empty pool** before it holds anything: sync, delete a
   file, `snapraid fix` it back. If you have not rehearsed a restore you do not have
   parity, you have a feeling.

**Gate:** `snapraid sync` and `snapraid scrub` complete clean on the empty pool, and a
deliberate file deletion has been recovered from parity.

---

## Phase 4 — Move the data

Two routes. Take the first if the disks allow it.

### Route A — adopt the unraid disks (no copying)

Works because unraid data disks are plain single-disk XFS with no striping
(STORAGE §5).

1. Pick a batch of data disks. Note exactly which files are on them.
2. Move them to the NixOS box. Mount **read-only**. Verify contents.
3. Remount read-write, add to mergerfs and to `services.snapraid.dataDisks`.
4. `snapraid sync`, then `snapraid scrub`.
5. Only then remove those disks from the unraid array.
6. Repeat. **The unraid parity disk is the last thing you touch** — it is your rollback
   for every batch before it.

Cost: near zero copying. Risk: the array is degraded during the transition, so batches
must be small and verified.

### Route B — copy over the network

If disks are btrfs/zfs formatted, if you would rather not disturb the running array, or
if you have enough new disks to build the pool standalone.

```bash
rsync -aHAX --info=progress2 --partial /mnt/user/media/ /mnt/storage/media/
```

`-H` is not optional — without it every hardlink between downloads and the library
becomes a full copy. Run it repeatedly until the final pass is short, then do a last
pass with services stopped.

Cost: days on gigabit for a large library. Risk: low; the source is untouched.

**Gate for either route:** file counts and a spot-check of checksums match, parity has
synced and scrubbed clean, and hardlinks survived (`find /mnt/storage -links +1 | head`).

---

## Phase 5 — Migrate the services, in waves

Order is by blast radius, lowest first. Prefer native NixOS modules; see
ARCHITECTURE §5 for the full mapping.

**Wave 1 — stateless and personal.** microbin, barracudas4-website,
laundry-notifier, flaresolverr. Nothing depends on them. This is where you learn how
`services.*` vs `oci-containers` feels on this box.

**Wave 2 — the *arr stack.** sonarr, radarr, bazarr, jackett (consider prowlarr
instead), lazylibrarian (or readarr), qbittorrent, overseerr, maintainerr, tdarr.
Their state is a config directory plus a SQLite database: stop the container, copy the
directory to the new location, fix ownership to the service user, start the native
unit. Fix root-folder paths to `/mnt/storage/...` **before** letting them scan, or
they will happily reorganise your library into the wrong place.

**Wave 3 — Plex.** Copy `Library/Application Support/Plex Media Server` — it is large
and it holds all your watch history and metadata; do not recreate it. Point libraries
at the new paths, enable hardware transcoding, confirm NVENC actually engages
(`nvidia-smi` during a transcode, not just the Plex checkbox).

**Wave 4 — Immich and paperless.** The two with real databases, so the two that need
`pg_dump`/`pg_restore` rather than a file copy. Both consolidate dramatically:

- `services.immich` runs server, machine learning, Postgres and Redis from one module.
  **The `modules/services/immich-ml.nix` offload container in this repo becomes dead
  code** — there is no longer a remote Immich server to offload from. Delete it.
- `services.paperless` with `configureTika = true` replaces the paperless, tika and
  gotenberg containers in one option.

Dump on unraid, restore here, verify the photo/document count matches, then re-run ML
jobs on the GPU.

**Wave 5 — network and ingress, last.** cloudflared, cloudflareddns, and finally DNS.
Before moving DNS: set a **secondary resolver** on the router that is not this box.
Then move pihole (container) or switch to blocky/adguardhome. Verify name resolution
survives a deliberate `nixos-rebuild` of the new server.

**Gate per wave:** the service works for several days on the new box before the old one
is stopped. Keep the unraid containers stopped-but-present, not deleted, until the
whole migration is done.

---

## Phase 6 — Close the gaps consolidation opened

- **Backups.** restic/borg from the new box to the wiped unraid hardware, plus offsite
  for photos, documents and service state. Test a restore — an untested backup is a
  hypothesis.
- **ZFS snapshots** via `services.sanoid` on the fast tier, so a bad rebuild or a
  botched upgrade is a rollback.
- **Monitoring and alerts.** `services.prometheus.exporters` + grafana, or netdata for
  something simpler. Route SnapRAID sync failures and SMART warnings somewhere you will
  actually see them; unraid used to nag you and now nothing will.
- **Reverse proxy + auth.** nginx or caddy in front of the web UIs, `services.authelia`
  for anything reachable from outside.
- **Homepage.** `services.homepage-dashboard` to replace the unraid docker page.

---

## Phase 7 — AI backend and GPU arbitration

Deliberately last: it is the least critical service and the most fiddly.

1. Add `host.ai.backend` and switch to `llama-swap` + CUDA `llama-cpp`
   (AI-BACKEND §5).
2. Repoint Open WebUI at whichever backend is active.
3. Decide the GPU policy for real:
   - **No passthrough VM (recommended):** delete or disable
     `modules/virtualisation/gpu-passthrough.nix`. Everything shares the card by VRAM
     budget and the whole class of bind/unbind bugs disappears.
   - **Passthrough kept:** extend `host.gpu.hostServices` to include Plex, Tdarr,
     Immich and the LLM unit, and accept that starting the VM degrades the media stack
     to CPU transcoding.

---

## Phase 8 — Retire unraid

Only after the new server has run everything for **at least two weeks**.

1. Confirm backups from the new box to somewhere else are running and restorable.
2. Wipe the unraid box and rebuild it as a pure backup target.
3. Delete the old containers and the now-dead modules in this repo
   (`immich-ml.nix`, and the passthrough modules if the VM was dropped).
4. Update README and ARCHITECTURE to describe the world as it actually is.

---

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Data loss while moving disks | Low, catastrophic | Batches, read-only first mount, unraid parity untouched until last |
| Not enough SATA ports | **High** | Inventory in phase 0; LSI HBA in IT mode |
| Hardlinks broken → library doubles in size | **High** | `rsync -H`, `use_ino` in mergerfs, downloads and media under one mount |
| CUDA rebuilds take hours | **High** | CUDA binary cache before the first rebuild |
| DNS outage takes the LAN down | Medium, very visible | Secondary resolver off-box, DNS migrated last |
| GPU contention (Plex + Immich + LLM) | Medium | VRAM budget, llama-swap TTL, explicit `-ngl` |
| *arr services reorganise the library onto wrong paths | Medium, painful | Fix root folders before first scan; take a config backup first |
| 2700X saturated by Tdarr + OCR + transcode | Medium | `CPUQuota=`/`CPUWeight=` on the greedy units; schedule Tdarr overnight |
| Single machine = single point of failure | Certain | Backups, tested restores, NixOS generation rollback |

## Effort estimate

| Phase | Effort |
|---|---|
| 0 — inventory | an evening |
| 1 — fix tree | an evening |
| 2 — hardware bring-up | a day |
| 3 — build array | a day, plus scrub time |
| 4 — data migration | an afternoon (route A) to several days (route B) |
| 5 — services, five waves | a few weeks of evenings, deliberately paced |
| 6 — backups/monitoring | a weekend |
| 7 — AI backend | an evening |
| 8 — retire unraid | a day |
