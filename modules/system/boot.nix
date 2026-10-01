{ config, lib, ... }:
let
  vendor = config.host.cpuVendor;
in
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.cpu.amd.updateMicrocode = lib.mkIf (vendor == "amd") true;
  hardware.cpu.intel.updateMicrocode = lib.mkIf (vendor == "intel") true;

  hardware.enableRedistributableFirmware = true;
}
