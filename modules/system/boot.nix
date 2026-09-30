{ config, lib, ... }:
# Bootloader, CPU microcode, and IOMMU enablement.
# IOMMU is required for VFIO GPU passthrough; the exact kernel param depends on
# the CPU vendor, driven by `host.cpuVendor`.
let
  vendor = config.host.cpuVendor;
  iommuParam = if vendor == "amd" then "amd_iommu=on" else "intel_iommu=on";
in
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelParams = [
    iommuParam
    # Passthrough / performance: only use the IOMMU for devices that need it.
    "iommu=pt"
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkIf (vendor == "amd") true;
  hardware.cpu.intel.updateMicrocode = lib.mkIf (vendor == "intel") true;

  hardware.enableRedistributableFirmware = true;
}
