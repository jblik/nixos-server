{ ... }:
# Per-host entry point. Imports the machine's generated hardware config and
# sets the site-specific knobs declared in modules/options.nix.
{
  imports = [
    ./hardware-configuration.nix
  ];

  host = {
    hostname = "nixos-server";
    timezone = "Europe/Brussels";

    # Assumed AMD; flip to "intel" if needed (see modules/options.nix).
    cpuVendor = "amd";

    # Tighten to your real subnet.
    lanCidr = "192.168.0.0/16";

    # === FILL IN ON THE REAL MACHINE ===
    # lspci -nn  | grep -i nvidia   -> vendorIds (GPU + HDMI audio)
    # lspci -D   | grep -i nvidia   -> busIds
    gpu = {
      vendorIds = [
        # "10de:XXXX"  # GPU
        # "10de:YYYY"  # GPU HDMI audio
      ];
      busIds = [
        # "0000:01:00.0"  # GPU
        # "0000:01:00.1"  # GPU HDMI audio
      ];
    };

    # === STORAGE — FILL IN ON THE REAL MACHINE ===
    # The array that replaces unraid. See docs/STORAGE.md for the design and
    # docs/MIGRATION.md phases 3–4 for the order to build it in.
    #
    #   lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINT   # inventory
    #   blkid                                               # confirm XFS per disk
    #
    # Mount each data disk by-id with `noatime` (in hardware-configuration.nix),
    # then list them here. Leaving `dataDisks` empty disables the bulk tier, so
    # this whole block is safe to grow into.
    storage = {
      # Fast tier — create the pool by hand first, then name it here:
      #   zpool create -o ashift=12 -O compression=zstd -O atime=off fast \
      #     mirror /dev/disk/by-id/<ssd-a> /dev/disk/by-id/<ssd-b>
      # fastPool = "fast";
      # hostId = "xxxxxxxx";   # head -c 8 /etc/machine-id

      # Bulk tier — one entry per data disk.
      dataDisks = {
        # d1 = "/mnt/disk1";
        # d2 = "/mnt/disk2";
        # d3 = "/mnt/disk3";
      };
      parityFiles = [
        # "/mnt/parity1/snapraid.parity"   # must be >= the largest data disk
      ];

      # spinDownSeconds = 900;   # unraid-style idle spin-down (HDDs only)
    };

    # AI backend. "llama-swap" (default) runs CUDA llama.cpp with explicit VRAM
    # budgeting; "ollama" is the simpler fallback. See docs/AI-BACKEND.md.
    ai = {
      # backend = "llama-swap";
      models = {
        # Drop GGUF files in host.ai.modelsDir (default /var/lib/models):
        # "qwen3-8b" = {
        #   file = "Qwen3-8B-Q4_K_M.gguf";
        #   contextSize = 16384;
        # };
      };
    };
  };

  # Do not change after install unless you know what you're doing.
  system.stateVersion = "26.05";
}
