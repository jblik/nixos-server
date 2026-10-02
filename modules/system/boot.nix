{ config, lib, ... }:
let
  vendor = config.host.cpuVendor;
in
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.memtest86.enable = true;

  hardware.cpu.amd.updateMicrocode = lib.mkIf (vendor == "amd") true;
  hardware.cpu.intel.updateMicrocode = lib.mkIf (vendor == "intel") true;

  hardware.enableRedistributableFirmware = true;
}
