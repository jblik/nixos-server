{ ... }:
# PLACEHOLDER — replace this entire file with the output of
#   sudo nixos-generate-config --show-hardware-config
# run on the real machine (it detects disks, filesystems, kernel modules, etc).
#
# Until then this file only exists so the flake evaluates. It intentionally does
# NOT define filesystems/bootloader device, so a real build will fail loudly
# rather than silently producing a broken system.
{
  # boot.initrd.availableKernelModules = [ ... ];
  # fileSystems."/" = { device = "/dev/disk/by-uuid/..."; fsType = "ext4"; };
  # swapDevices = [ ];

  nixpkgs.hostPlatform = "x86_64-linux";
}
