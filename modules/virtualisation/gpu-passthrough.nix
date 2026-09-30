{
  config,
  lib,
  pkgs,
  ...
}:
# Single-GPU dynamic passthrough.
#
# Default: GPU bound to nvidia, used by the AI/ML services. When a passthrough
# VM (host.gpu.passthroughVms) starts, libvirt's qemu hook releases the GPU from
# the host; libvirt then binds vfio-pci to the card (via `managed='yes'`
# <hostdev> in the domain XML). On shutdown the reverse happens and the AI/ML
# services come back.
#
# Flow per VM lifecycle:
#   prepare  -> stop host GPU services, unload nvidia modules  (host lets go)
#   <libvirt binds vfio-pci, VM runs with full GPU>
#   release  -> reload nvidia modules, start host GPU services (host reclaims)
let
  hostServices = lib.concatStringsSep " " config.host.gpu.hostServices;
  passthroughVms = lib.concatStringsSep " " config.host.gpu.passthroughVms;

  systemctl = "${pkgs.systemd}/bin/systemctl";
  modprobe = "${pkgs.kmod}/bin/modprobe";

  nvidiaModules = "nvidia_drm nvidia_modeset nvidia_uvm nvidia";

  gpuStatus = pkgs.writeShellScriptBin "gpu-status" ''
    echo "== GPU driver binding =="
    ${pkgs.pciutils}/bin/lspci -nnk -d 10de: || true
    echo
    echo "== Host GPU services =="
    ${systemctl} --no-pager --plain list-units '${
      lib.concatStringsSep "' '" config.host.gpu.hostServices
    }' || true
  '';
in
{
  virtualisation.libvirtd.hooks.qemu.gpu-passthrough = pkgs.writeShellScript "gpu-passthrough-hook" ''
    set -u
    GUEST="$1"
    OPERATION="$2"

    # Only act on designated passthrough VMs.
    case " ${passthroughVms} " in
      *" $GUEST "*) ;;
      *) exit 0 ;;
    esac

    case "$OPERATION" in
      prepare)
        # Hand the GPU to the VM: stop CUDA workloads, then free the driver.
        ${systemctl} stop ${hostServices} || true
        sleep 2
        ${modprobe} -r ${nvidiaModules} || true
        ;;
      release)
        # Reclaim the GPU for the host and resume CUDA workloads.
        ${modprobe} ${nvidiaModules} || true
        ${systemctl} start ${hostServices} || true
        ;;
    esac
  '';

  environment.systemPackages = [ gpuStatus ];
}
