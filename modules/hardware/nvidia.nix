{ config, ... }:
# NVIDIA proprietary driver. The one GPU is shared by Plex and Tdarr (NVENC)
# and, once enabled, the AI backend.
{
  hardware.graphics.enable = true;

  # Loads the nvidia kernel module (also on a headless box — X is not started).
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = false; # headless, no GUI control panel
    powerManagement.enable = false;

    # Proprietary kernel modules. The 3060 (Ampere) also supports the open
    # modules; switch to `true` to use them.
    open = false;

    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
