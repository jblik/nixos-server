{ ... }:
# VFIO is made *available* but does NOT claim the GPU at boot.
#
# Default state = GPU bound to `nvidia` for AI/ML. The libvirt qemu hook
# detaches the card to vfio-pci only while a passthrough VM is running, then
# rebinds nvidia on shutdown. That's why there is deliberately no
# `boot.blacklistedKernelModules = [ "nvidia" ]` and no `vfio-pci.ids=` here —
# doing either would steal the GPU from the AI services permanently.
{
  boot.kernelModules = [
    "vfio_pci"
    "vfio"
    "vfio_iommu_type1"
  ];
}
