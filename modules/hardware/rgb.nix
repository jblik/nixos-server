{ lib, pkgs, ... }:
# All lighting off. The board LEDs and everything on its ARGB headers (fans,
# PSU) hang off the Aura USB controller; i2c-dev lets OpenRGB also find RGB on
# the GPU and RAM, if any.
{
  boot.kernelModules = [ "i2c-dev" ];

  systemd.services.rgb-off = {
    description = "Turn off all RGB lighting";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe pkgs.openrgb} --mode static --color 000000";
    };
  };
}
