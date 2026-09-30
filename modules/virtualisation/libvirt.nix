{ pkgs, ... }:
# QEMU/KVM via libvirt. UEFI (OVMF) + swtpm so modern guests (SteamOS, Windows)
# install cleanly. GPU passthrough is wired up in gpu-passthrough.nix.
{
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore"; # don't auto-start VMs (they'd grab the GPU on boot)
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true; # TPM 2.0 for modern guests
      # OVMF/UEFI firmware ships with QEMU by default in 26.05.
    };
  };

  # GUI manager (use over SSH X-forward or from another machine).
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    virt-manager
    looking-glass-client # low-latency display from the passthrough VM
  ];
}
