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

    # Proprietary kernel modules. Switch to `true` for the open modules if you
    # have a Turing-or-newer card and prefer them.
    open = false;

    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
}
