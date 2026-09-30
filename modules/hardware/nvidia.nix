{ config, ... }:
# NVIDIA proprietary driver + CUDA, bound to the GPU by default so the AI/ML
# services can use it. It is detached to vfio-pci on demand for VM passthrough
# (see modules/virtualisation/gpu-passthrough.nix) and rebound afterwards.
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # needed for Steam / 32-bit GL in VMs and game streaming
  };

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

  # Lets podman/docker containers (e.g. Immich ML) use the GPU via CDI.
  hardware.nvidia-container-toolkit.enable = true;
}
